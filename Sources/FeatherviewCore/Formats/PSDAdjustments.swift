import CoreGraphics
import Foundation

/// Photoshop adjustment layers (Adobe's Photoshop File Formats Specification, "Adjustment layers"):
/// each tagged block becomes a per-pixel function on 8-bit-equivalent RGB values in 0…1.
public enum PSDAdjustments {
    public typealias Adjust = @Sendable (inout SIMD3<Float>) -> Void

    /// The adjustment a tagged block describes, nil for keys it doesn't know. Throws
    /// `OwnDecodeError.corrupt` on damaged data.
    public static func adjustment(key: String, data: Data) throws -> Adjust? {
        var r = Reader(bytes: [UInt8](data))
        switch key {
        case "nvrt":
            return { $0 = 1 - $0 }
        case "thrs":
            let level = Float(try r.u16())
            return { c in c = SIMD3(repeating: (lum(c) * 255).rounded() >= level ? 1 : 0) }
        case "post":
            let levels = Float(max(2, try r.u16()))
            return { c in c = (c * levels).rounded(.down).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: levels - 1)) / (levels - 1) }
        case "levl": return try levels(&r)
        case "curv": return try curves(&r)
        case "brit":
            let brightness = Float(try r.i16()), contrast = Float(try r.i16()), mean = Float(try r.i16())
            return legacyBrightness(brightness, contrast, mean / 255)
        case "CgEd":
            let d = try PSDDescriptor.versioned(data)
            let brightness = try number(d["Brgh"]) ?? 0, contrast = try number(d["Cntr"]) ?? 0, mean = (try number(d["means"]) ?? 127) / 255
            if d["useLegacy"] == .bool(true) { return legacyBrightness(brightness, contrast, mean) }
            // Photoshop doesn't publish its curve; this one keeps black and white where they are.
            let exponent = pow(2, -brightness / 100), factor = 1 + contrast / 100
            return { c in
                c = c.clamped(lowerBound: .zero, upperBound: .one)
                c = SIMD3(pow(c.x, exponent), pow(c.y, exponent), pow(c.z, exponent))
                c = clamp01((c - mean) * factor + mean)
            }
        case "hue2": return try hueSaturation(&r)
        case "blnc": return try colourBalance(&r)
        case "blwh": return try blackAndWhite(try PSDDescriptor.versioned(data))
        case "mixr": return try channelMixer(&r)
        case "expA":
            _ = try r.u16()
            let exposure = try r.f32(), offset = try r.f32(), gamma = try r.f32()
            guard exposure.isFinite, offset.isFinite, gamma.isFinite, gamma > 0 else { throw OwnDecodeError.corrupt }
            let scale = pow(2, exposure)
            return { c in
                for i in 0..<3 {
                    let l = max(0, linear(c[i]) * scale + offset)
                    c[i] = min(1, encoded(pow(l, 1 / gamma)))
                }
            }
        case "vibA":
            let d = try PSDDescriptor.versioned(data)
            let vibrance = (try number(d["vibrance"]) ?? 0) / 100, saturation = (try number(d["Strt"]) ?? 0) / 100
            return { c in c = saturate(c, by: min(max(saturation + vibrance * (1 - (c.max() - c.min())), -1), 1)) }
        case "phfl": return try photoFilter(&r)
        case "selc": return try selectiveColour(&r)
        case "grdm": return try gradientMap(&r)
        default:
            // shortcut: colour lookup (`clrL`) and any other adjustment are drawn without, until the corpus shows them often.
            return nil
        }
    }

    // MARK: - Levels and Curves

    /// Applies each channel's own table, then the composite one (as Photoshop's composites show), folded into one
    /// flat table per channel so a pixel costs three plain lookups.
    private static func tables(_ t: [[Float]]) -> Adjust {
        let flat = (1...3).flatMap { channel in (0...255).map { lookup(t[0], lookup(t[channel], Float($0) / 255)) } }
        return { c in
            for i in 0..<3 {
                let x = min(max(c[i], 0), 1) * 255, j = min(Int(x), 254), k = i * 256 + j
                c[i] = flat[k] + (flat[k + 1] - flat[k]) * (x - Float(j))
            }
        }
    }

    private static func levels(_ r: inout Reader) throws -> Adjust {
        _ = try r.u16()
        var t: [[Float]] = []
        for _ in 0..<4 {
            let inFloor = Float(try r.u16()), inCeiling = Float(try r.u16())
            let outFloor = Float(try r.u16()), outCeiling = Float(try r.u16()), gamma = Float(try r.u16()) / 100
            guard inCeiling > inFloor, gamma > 0 else { throw OwnDecodeError.corrupt }
            t.append((0...255).map { i in
                let v = pow(min(max((Float(i) - inFloor) / (inCeiling - inFloor), 0), 1), 1 / gamma)
                return min(max(outFloor + v * (outCeiling - outFloor), 0), 255) / 255
            })
        }
        return tables(t)
    }

    /// The curves stored for the channels in the bitmap, as point lists; the curves extra data ('Crv ') that may
    /// follow repeats them and is left unread.
    private static func curves(_ r: inout Reader) throws -> Adjust? {
        // shortcut: a non-zero first byte is a curves form Adobe's spec doesn't describe and no corpus file uses; the layer
        // is drawn without it, until a real file shows its layout.
        guard try r.u8() == 0 else { return nil }
        _ = try r.u16()
        let channels = try r.u32()
        let identity = (0...255).map { Float($0) / 255 }
        var t = Array(repeating: identity, count: 4)
        for bit in 0..<32 where channels & 1 << bit != 0 {
            let count = try r.u16()
            var points: [(x: Float, y: Float)] = []
            for _ in 0..<count {
                let output = Float(try r.u16()), input = Float(try r.u16())
                points.append((input, output))
            }
            let curve = spline(points)
            // Bits past blue belong to other colour modes' channels.
            if bit < 4 { t[bit] = curve }
        }
        return tables(t)
    }

    /// A natural cubic spline through the points (input, output in 0…255), flat past its ends, as a
    /// 256-entry table in 0…1.
    private static func spline(_ unsorted: [(x: Float, y: Float)]) -> [Float] {
        var p: [(x: Float, y: Float)] = []
        for point in unsorted.sorted(by: { $0.x < $1.x }) where point.x != p.last?.x { p.append(point) }
        guard p.count >= 2 else { return (0...255).map { Float($0) / 255 } }
        let n = p.count
        let h = (0..<n - 1).map { p[$0 + 1].x - p[$0].x }
        // Second derivatives, zero at both ends; the tridiagonal system solved by forward elimination.
        var m = [Float](repeating: 0, count: n), diagonal = [Float](repeating: 1, count: n), rhs = [Float](repeating: 0, count: n)
        for i in 1..<n - 1 {
            diagonal[i] = 2 * (h[i - 1] + h[i])
            rhs[i] = 6 * ((p[i + 1].y - p[i].y) / h[i] - (p[i].y - p[i - 1].y) / h[i - 1])
            if i > 1 {
                let f = h[i - 1] / diagonal[i - 1]
                diagonal[i] -= f * h[i - 1]
                rhs[i] -= f * rhs[i - 1]
            }
        }
        for i in stride(from: n - 2, through: 1, by: -1) {
            m[i] = (rhs[i] - h[i] * m[i + 1]) / diagonal[i]
        }
        var segment = 0
        return (0...255).map { i in
            let x = Float(i)
            let y: Float
            if x <= p[0].x {
                y = p[0].y
            } else if x >= p[n - 1].x {
                y = p[n - 1].y
            } else {
                while x > p[segment + 1].x { segment += 1 }
                let a = (p[segment + 1].x - x) / h[segment], b = 1 - a
                y = a * p[segment].y + b * p[segment + 1].y
                    + ((a * a * a - a) * m[segment] + (b * b * b - b) * m[segment + 1]) * h[segment] * h[segment] / 6
            }
            return min(max(y, 0), 255) / 255
        }
    }

    // MARK: - Brightness/Contrast

    private static func legacyBrightness(_ brightness: Float, _ contrast: Float, _ mean: Float) -> Adjust {
        let factor = contrast >= 0 ? 1 / max(1 - contrast / 100, 1 / 255) : 1 + contrast / 100
        return { c in c = clamp01((c + brightness / 255 - mean) * factor + mean) }
    }

    // MARK: - Hue/Saturation

    private static func hueSaturation(_ r: inout Reader) throws -> Adjust {
        _ = try r.u16()
        let colorize = try r.u8() != 0
        _ = try r.u8()
        let colorizeHue = Float(try r.i16()), colorizeSaturation = Float(try r.i16()) / 100, colorizeLightness = Float(try r.i16()) / 100
        let master = SIMD3<Float>(Float(try r.i16()), Float(try r.i16()) / 100, Float(try r.i16()) / 100)
        var ranges: [(ramp: SIMD4<Float>, settings: SIMD3<Float>)] = []
        for _ in 0..<6 {
            let ramp = SIMD4<Float>(Float(try r.i16()), Float(try r.i16()), Float(try r.i16()), Float(try r.i16()))
            ranges.append((ramp, SIMD3(Float(try r.i16()), Float(try r.i16()) / 100, Float(try r.i16()) / 100)))
        }
        // The rules below are what Photoshop's composites show (Adobe doesn't publish them): HSL throughout; the six
        // ranges first, weighted by hue and summed, then the master settings.
        if colorize {
            let base = rotate(SIMD3(1, 0, 0), by: colorizeHue)
            return { c in
                let l = lighten((c.max() + c.min()) / 2, by: colorizeLightness)
                c = l + (base - 0.5) * (1 - abs(2 * l - 1)) * colorizeSaturation
            }
        }
        return { [ranges] c in
            var shift = SIMD3<Float>.zero  // hue, saturation (as `gain`s), lightness
            if c.max() > c.min() {
                let h = hue(c)
                for range in ranges {
                    let w = weight(h, range.ramp)
                    if w > 0 { shift += w * SIMD3(range.settings.x, gain(range.settings.y), range.settings.z) }
                }
            }
            // A range's lightness moves the colour above its darkest channel: toward that channel's grey or the brightest's.
            let lightness = min(max(shift.z, -1), 1), lo = c.min(), hi = c.max()
            c = lightness < 0 ? lo + (c - lo) * (1 + lightness) : c + (hi - c) * lightness
            c = scaleSaturation(rotate(c, by: shift.x), by: 1 + shift.y)
            c = lighten(c, by: master.z)
            c = scaleSaturation(rotate(c, by: master.x), by: 1 + gain(master.y))
        }
    }

    /// A saturation setting (−1…1) as the change of the HSL saturation's factor: −100 % takes it all, +100 % saturates fully.
    private static func gain(_ amount: Float) -> Float {
        amount <= 0 ? amount : amount >= 1 ? .infinity : amount / (1 - amount)
    }

    /// The HSL saturation times `factor` (at least 0, at most full), hue and lightness kept.
    private static func scaleSaturation(_ c: SIMD3<Float>, by factor: Float) -> SIMD3<Float> {
        let hi = c.max(), lo = c.min(), l = (hi + lo) / 2, room = 1 - abs(hi + lo - 1)
        guard hi > lo, room > 0 else { return c }
        let s = (hi - lo) / room
        return clamp01(l + (c - l) * min(max(factor, 0), 1 / s))
    }

    /// How much a hue (degrees) belongs to a range: ramps up from its first value to its second,
    /// full to its third, down to its fourth; ranges may wrap past 360.
    private static func weight(_ h: Float, _ r: SIMD4<Float>) -> Float {
        func from(_ v: Float) -> Float {
            let x = (v - r.x).truncatingRemainder(dividingBy: 360)
            return x < 0 ? x + 360 : x
        }
        let t = from(h), b = from(r.y), c = max(from(r.z), b), d = max(from(r.w), c)
        if t < b { return t / b }
        if t <= c { return 1 }
        if t < d { return (d - t) / (d - c) }
        return 0
    }

    /// The HSV hue in degrees.
    private static func hue(_ c: SIMD3<Float>) -> Float {
        let hi = c.max(), lo = c.min(), d = hi - lo
        guard d > 0 else { return 0 }
        let h: Float
        if hi == c.x { h = (c.y - c.z) / d } else if hi == c.y { h = 2 + (c.z - c.x) / d } else { h = 4 + (c.x - c.y) / d }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Turns the hue keeping HSV's value and saturation.
    private static func rotate(_ c: SIMD3<Float>, by degrees: Float) -> SIMD3<Float> {
        let hi = c.max(), lo = c.min()
        guard degrees != 0, hi > lo else { return c }
        var h = (hue(c) + degrees).truncatingRemainder(dividingBy: 360) / 60
        if h < 0 { h += 6 }
        func channel(_ n: Float) -> Float {
            let k = (n + h).truncatingRemainder(dividingBy: 6)
            return hi - (hi - lo) * max(0, min(k, 4 - k, 1))
        }
        return SIMD3(channel(5), channel(3), channel(1))
    }

    private static func saturate(_ c: SIMD3<Float>, by amount: Float) -> SIMD3<Float> {
        let l = lum(c)
        return clamp01(setLum(l + (c - l) * (1 + amount), l))
    }

    private static func lighten(_ c: SIMD3<Float>, by amount: Float) -> SIMD3<Float> {
        clamp01(amount >= 0 ? c + (1 - c) * amount : c * (1 + amount))
    }

    private static func lighten(_ v: Float, by amount: Float) -> Float {
        min(max(amount >= 0 ? v + (1 - v) * amount : v * (1 + amount), 0), 1)
    }

    // MARK: - Colour Balance, Black & White, Channel Mixer, Photo Filter

    private static func colourBalance(_ r: inout Reader) throws -> Adjust {
        var shifts: [SIMD3<Float>] = []
        for _ in 0..<3 { shifts.append(SIMD3(Float(try r.i16()), Float(try r.i16()), Float(try r.i16())) / 255) }
        let tones = shifts
        let preserve = r.remaining > 0 ? try r.u8() != 0 : false
        return { c in
            let l = lum(c)
            let shadows = max(0, 1 - 2 * l), highlights = max(0, 2 * l - 1), midtones = 1 - shadows - highlights
            let shifted = clamp01(c + tones[0] * shadows + tones[1] * midtones + tones[2] * highlights)
            c = preserve ? clamp01(setLum(shifted, l)) : shifted
        }
    }

    private static func blackAndWhite(_ d: PSDDescriptor) throws -> Adjust {
        // Weights of red, yellow, green, cyan, blue, magenta, Photoshop's defaults where a key is missing.
        let w = try zip(["Rd  ", "Yllw", "Grn ", "Cyn ", "Bl  ", "Mgnt"], [40, 60, 40, 60, 20, 80] as [Float]).map { (try number(d[$0]) ?? $1) / 100 }
        let tint: SIMD3<Float>? = if d["useTint"] == .bool(true), case .object(let colour)? = d["tintColor"] {
            SIMD3(try number(colour["Rd  "]) ?? 0, try number(colour["Grn "]) ?? 0, try number(colour["Bl  "]) ?? 0) / 255
        } else { nil }
        let primaries = SIMD3(w[0], w[2], w[4]), secondaries = SIMD3(w[3], w[5], w[1])  // by darkest: cyan, magenta, yellow
        return { c in
            // The grey is the darkest channel plus the part shared by the two brightest (a secondary
            // colour) plus the brightest's own part (a primary), each weighted by its colour.
            let (h, m, l) = order(c)
            let hi = c[h], mid = c[m], lo = c[l]
            let grey = min(max(lo + (mid - lo) * secondaries[l] + (hi - mid) * primaries[h], 0), 1)
            c = tint.map { clamp01(setLum($0, grey)) } ?? SIMD3(repeating: grey)
        }
    }

    private static func channelMixer(_ r: inout Reader) throws -> Adjust {
        _ = try r.u16()
        let monochrome = try r.u16() != 0
        var rows: [(weights: SIMD3<Float>, constant: Float)] = []
        for _ in 0..<3 {
            let weights = SIMD3<Float>(Float(try r.i16()), Float(try r.i16()), Float(try r.i16())) / 100
            _ = try r.i16()
            rows.append((weights, Float(try r.i16()) / 100))
        }
        let mix = monochrome ? Array(repeating: rows[0], count: 3) : rows
        return { c in
            let source = c
            for i in 0..<3 { c[i] = min(max((source * mix[i].weights).sum() + mix[i].constant, 0), 1) }
        }
    }

    private static func photoFilter(_ r: inout Reader) throws -> Adjust? {
        // shortcut: version 3 stores the colour as XYZ in a scale the corpus doesn't show, so it is drawn without; read it once a file has one.
        guard try r.u16() == 2 else { return nil }
        let space = try r.u16()
        let values = [try r.u16(), try r.u16(), try r.u16(), try r.u16()]
        let density = Float(min(try r.u32(), 100)) / 100, preserve = try r.u8() != 0
        guard let filter = colour(space: space, values) else { return nil }
        return { c in
            let filtered = c + (c * filter - c) * density
            c = preserve ? clamp01(setLum(filtered, lum(c))) : filtered
        }
    }

    // MARK: - Selective Colour, Gradient Map

    private static func selectiveColour(_ r: inout Reader) throws -> Adjust {
        _ = try r.u16()
        let relative = try r.u16() == 0
        // Records 0…9: unused, reds, yellows, greens, cyans, blues, magentas, whites, neutrals, blacks; each
        // as the change to cyan, magenta and yellow ink, black added to all three.
        var records: [SIMD3<Float>] = []
        for _ in 0..<10 {
            let a = SIMD4(Float(try r.i16()), Float(try r.i16()), Float(try r.i16()), Float(try r.i16())) / 100
            records.append(SIMD3(a.x, a.y, a.z) + a.w)
        }
        let whitesRecord = records[7], neutralsRecord = records[8], blacksRecord = records[9]
        return { [records] c in
            let (h, m, l) = order(c)
            let hi = c[h], mid = c[m], lo = c[l]
            let whites = max(0, 2 * lo - 1), blacks = max(0, 1 - 2 * hi)
            // The brightest channel's primary (reds, greens, blues) and the two brightest's secondary
            // (by the darkest: cyans, magentas, yellows).
            let change = (hi - mid) * records[1 + h * 2] + (mid - lo) * records[l == 0 ? 4 : l == 1 ? 6 : 2]
                + whites * whitesRecord + max(0, 1 - whites - blacks - (hi - lo)) * neutralsRecord + blacks * blacksRecord
            var ink = 1 - c
            ink += change * (relative ? ink : .one)
            c = clamp01(1 - ink)
        }
    }

    private static func gradientMap(_ r: inout Reader) throws -> Adjust? {
        let version = try r.u16()
        let reverse = try r.u8() != 0
        _ = try r.u8()
        // Version 3 adds the interpolation method ('Gcls' classic, 'Perc' perceptual, 'Lnr ' linear, …).
        // shortcut: every method mixes like classic (version 1), until the corpus oracle shows how far the others differ.
        if version == 3 { try r.skip(4) }
        try r.skip(Int(try r.u32()) * 2)
        let count = try r.u16()
        guard count > 0 else { throw OwnDecodeError.corrupt }
        var stops: [(location: Float, midpoint: Float, colour: SIMD3<Float>)] = []
        for _ in 0..<count {
            let location = Float(min(try r.u32(), 4096)) / 4096, midpoint = Float(min(max(try r.u32(), 1), 99)) / 100
            let space = try r.u16()
            let values = [try r.u16(), try r.u16(), try r.u16(), try r.u16()]
            _ = try r.u16()
            // shortcut: stops in a colour book (custom) space draw the layer without the map, until a file has one.
            guard let colour = colour(space: space, values) else { return nil }
            stops.append((location, midpoint, colour))
        }
        stops.sort { $0.location < $1.location }
        let table: [SIMD3<Float>] = (0...255).map { i in
            let t = reverse ? 1 - Float(i) / 255 : Float(i) / 255
            guard let right = stops.firstIndex(where: { $0.location >= t }) else { return stops[stops.count - 1].colour }
            guard right > 0, stops[right].location > stops[right - 1].location else { return stops[right].colour }
            let a = stops[right - 1], b = stops[right]
            let f = (t - a.location) / (b.location - a.location), m = b.midpoint
            // The midpoint is where the two colours mix half and half.
            let g = f < m ? 0.5 * f / m : 0.5 + 0.5 * (f - m) / (1 - m)
            return a.colour + (b.colour - a.colour) * g
        }
        return { c in
            let x = min(max(lum(c), 0), 1) * 255, i = min(Int(x), 254), f = x - Float(i)
            c = table[i] + (table[i + 1] - table[i]) * f
        }
    }

    // MARK: - Shared

    /// A colour structure's colour as RGB in 0…1: RGB (0), HSB (1), CMYK (2), Lab (7) and grey (8); nil for
    /// colour books and other spaces.
    private static func colour(space: Int, _ v: [Int]) -> SIMD3<Float>? {
        switch space {
        case 0:
            return SIMD3(Float(v[0]), Float(v[1]), Float(v[2])) / 65535
        case 1:
            let s = Float(v[1]) / 65535, b = Float(v[2]) / 65535
            return rotate(SIMD3(b, b * (1 - s), b * (1 - s)), by: Float(v[0]) / 65535 * 360)
        case 2:
            // 65535 is no ink; a plain product without an ink profile.
            return SIMD3(Float(v[0]), Float(v[1]), Float(v[2])) / 65535 * (Float(v[3]) / 65535)
        case 8:
            return SIMD3(repeating: 1 - Float(min(v[0], 10000)) / 10000)
        case 7:
            let lab = [CGFloat(v[0]) / 100, CGFloat(Int16(truncatingIfNeeded: v[1])) / 100, CGFloat(Int16(truncatingIfNeeded: v[2])) / 100, 1]
            guard let labSpace = CGColorSpace(labWhitePoint: [0.9642, 1, 0.8249], blackPoint: [0, 0, 0], range: [-128, 127, -128, 127]),
                  let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let rgb = CGColor(colorSpace: labSpace, components: lab)?.converted(to: srgb, intent: .relativeColorimetric, options: nil)?.components,
                  rgb.count >= 3 else { return nil }
            return clamp01(SIMD3(Float(rgb[0]), Float(rgb[1]), Float(rgb[2])))
        default:
            return nil
        }
    }

    /// Throws on NaN or infinity (also a double too large for a Float), which would paint NaN pixels.
    private static func number(_ value: PSDValue?) throws -> Float? {
        let v: Float? = switch value {
        case .int(let v)?: Float(v)
        case .double(let v)?: Float(v)
        case .unit(_, let v)?: Float(v)
        default: nil
        }
        guard v?.isFinite ?? true else { throw OwnDecodeError.corrupt }
        return v
    }

    /// A 256-entry table read between its entries.
    private static func lookup(_ t: [Float], _ v: Float) -> Float {
        let x = min(max(v, 0), 1) * 255, i = min(Int(x), 254)
        return t[i] + (t[i + 1] - t[i]) * (x - Float(i))
    }

    private static func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func encoded(_ l: Float) -> Float { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }

    /// The channels' indices from brightest to darkest; ties keep red, green, blue order.
    private static func order(_ c: SIMD3<Float>) -> (Int, Int, Int) {
        var (a, b, d) = (0, 1, 2)
        if c[b] > c[a] { swap(&a, &b) }
        if c[d] > c[b] { swap(&b, &d) }
        if c[b] > c[a] { swap(&a, &b) }
        return (a, b, d)
    }

    private static func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> { v.clamped(lowerBound: .zero, upperBound: .one) }

    /// W3C Compositing and Blending's luminosity, the same weights `PSDBlend` uses.
    private static func lum(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }

    /// W3C's SetLum: moves the colour to luminosity `l`, pulling it back into 0…1 along the grey axis.
    private static func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
        let c = c + (l - lum(c))
        let l = lum(c), n = c.min(), x = c.max()
        var out = c
        if n < 0, l > n { out = l + (out - l) * l / (l - n) }
        if x > 1, x > l { out = l + (out - l) * (1 - l) / (x - l) }
        return out
    }

    /// Big-endian reads; every read past the end throws `.corrupt`.
    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        var remaining: Int { bytes.count - position }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= remaining else { throw OwnDecodeError.corrupt }
            position += count
        }

        mutating func u8() throws -> UInt8 {
            try skip(1)
            return bytes[position - 1]
        }

        mutating func u16() throws -> Int {
            try skip(2)
            return Int(bytes[position - 2]) << 8 | Int(bytes[position - 1])
        }

        mutating func i16() throws -> Int { Int(Int16(truncatingIfNeeded: try u16())) }

        mutating func u32() throws -> Int { try u16() << 16 | u16() }

        mutating func f32() throws -> Float { Float(bitPattern: UInt32(try u32())) }
    }
}
