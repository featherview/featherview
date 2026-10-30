import CoreGraphics
import Foundation

/// Fill layers (solid colour `SoCo`, gradient `GdFl`, pattern `PtFl`) and vector masks (`vmsk`/`vsms`) of a
/// Photoshop file, drawn at a decode scale (Adobe's *Photoshop File Formats Specification*, "Additional
/// Layer Information" and "Path resource format").
public enum PSDFills {
    /// The layer's fill on the scaled canvas (`PSDLayers.scaled`), cut by its vector mask: over the whole
    /// scaled canvas, or over the vector mask's rect (its top-left is `vectorMask(…)`'s). Nil when the layer
    /// has no fill block. A layer that also stores pixels (shape layers do) is drawn from its fill.
    /// Throws `OwnDecodeError.corrupt` on damage or a pattern missing from `patterns`.
    public static func content(_ layer: PSDLayer, canvas: (width: Int, height: Int), patterns: [String: RGBAImage],
                               scale: Double) throws -> RGBAImage? {
        guard let key = ["SoCo", "GdFl", "PtFl"].first(where: { layer.blocks[$0] != nil }) else { return nil }
        let settings = try PSDDescriptor.versioned(layer.blocks[key]!)
        let sw = PSDLayers.scaledSize(canvas.width, scale), sh = PSDLayers.scaledSize(canvas.height, scale)
        let mask = try vectorMask(layer, canvas: canvas, scale: scale)
        let rect: PSDRect = mask?.rect ?? (0, 0, sh, sw)
        let w = rect.right - rect.left, h = rect.bottom - rect.top
        guard w > 0, h > 0 else { return RGBAImage(width: 0, height: 0, pixels: []) }

        let shade: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
        switch key {
        case "SoCo":
            let c = try colour(settings["Clr "])
            shade = { _, _ in (c.0, c.1, c.2, 255) }
        case "GdFl":
            // "Align with layer" puts the gradient in the shape's bounds, else in the canvas.
            let aligned = settings["Algn"] == .bool(true)
            let box: PSDRect = aligned ? mask?.bounds ?? (0, 0, sh, sw) : (0, 0, sh, sw)
            shade = try gradient(settings, box: box)
        default:
            shade = try pattern(settings, patterns: patterns, sx: Double(sw) / Double(canvas.width), sy: Double(sh) / Double(canvas.height))
        }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = y * w + x
                let (r, g, b, a) = shade(rect.left + x, rect.top + y)
                pixels[o * 4] = r
                pixels[o * 4 + 1] = g
                pixels[o * 4 + 2] = b
                let cover = mask.map { Int($0.pixels[o]) } ?? 255
                pixels[o * 4 + 3] = UInt8((Int(a) * cover + 127) / 255)
            }
        }
        return RGBAImage(width: w, height: h, pixels: pixels)
    }

    /// The layer's vector mask on the scaled canvas: its rect (the path's bounds on the canvas, the whole
    /// canvas when inverted or starting with a subtraction; empty when the path covers nothing), one byte
    /// per pixel of it, antialiased, and the path's own bounds, which may run past the canvas. Each shape
    /// (a subpath and the ones after it with operation −1) is filled even-odd, then combined with the
    /// shapes before it by its operation: 0 exclude, 1 combine, 2 subtract, 3 intersect. Without shapes, an
    /// initial fill record of 1 reveals the whole canvas, else nothing (the reverse when inverted).
    /// Nil without a vector mask or when it's disabled.
    public static func vectorMask(_ layer: PSDLayer, canvas: (width: Int, height: Int),
                                  scale: Double) throws -> (rect: PSDRect, pixels: [UInt8], bounds: PSDRect)? {
        guard let data = layer.blocks["vmsk"] ?? layer.blocks["vsms"] else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw OwnDecodeError.corrupt }
        func be(_ at: Int, _ n: Int) -> Int { bytes[at..<at + n].reduce(0) { $0 << 8 | Int($1) } }
        let flags = be(4, 4)
        if flags & 4 != 0 { return nil }
        var inverted = flags & 1 != 0

        let sw = PSDLayers.scaledSize(canvas.width, scale), sh = PSDLayers.scaledSize(canvas.height, scale)
        // Knots: preceding control point, anchor, leaving control point; each vertical then horizontal,
        // signed 8.24 fractions of the canvas.
        func point(_ at: Int) -> CGPoint {
            func fixed(_ at: Int) -> Double { Double(Int32(truncatingIfNeeded: be(at, 4))) / 16_777_216 }
            return CGPoint(x: fixed(at + 4) * Double(sw), y: fixed(at) * Double(sh))
        }
        var subpaths: [(closed: Bool, operation: Int, knots: [[CGPoint]])] = []
        var startsFull = false
        for at in stride(from: 8, through: bytes.count - 26, by: 26) {
            switch be(at, 2) {
            case 0, 3: subpaths.append((be(at, 2) == 0, Int(Int16(truncatingIfNeeded: be(at + 4, 2))), []))
            case 1, 2, 4, 5:
                guard !subpaths.isEmpty else { throw OwnDecodeError.corrupt }
                subpaths[subpaths.count - 1].knots.append([point(at + 2), point(at + 10), point(at + 18)])
            case 8: startsFull = be(at + 2, 2) == 1  // initial fill: the fill starts with every pixel
            default: break
            }
        }
        var shapes: [(operation: Int, path: CGMutablePath)] = []
        for subpath in subpaths where !subpath.knots.isEmpty {
            if subpath.operation != -1 || shapes.isEmpty { shapes.append((subpath.operation, CGMutablePath())) }
            let path = shapes[shapes.count - 1].path, knots = subpath.knots
            path.move(to: knots[0][1])
            for k in knots.indices.dropFirst() { path.addCurve(to: knots[k][1], control1: knots[k - 1][2], control2: knots[k][0]) }
            if subpath.closed { path.addCurve(to: knots[0][1], control1: knots[knots.count - 1][2], control2: knots[0][0]) }
            path.closeSubpath()
        }

        // Photoshop draws only the shapes when there are any; the initial fill decides an empty mask.
        if shapes.isEmpty, startsFull { inverted.toggle() }
        let all = shapes.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        let bounds: PSDRect = all.isNull || all.isEmpty ? (0, 0, sh, sw)
            : (Int(all.minY.rounded(.down)), Int(all.minX.rounded(.down)), Int(all.maxY.rounded(.up)), Int(all.maxX.rounded(.up)))
        // A first subtraction cuts from everything, so it covers the canvas outside the path too.
        var rect: PSDRect = (0, 0, sh, sw)
        if !inverted, shapes.first?.operation != 2 {
            guard !all.isNull, !all.isEmpty else { return ((0, 0, 0, 0), [], bounds) }
            rect = (max(0, bounds.top), max(0, bounds.left), min(sh, bounds.bottom), min(sw, bounds.right))
            guard rect.bottom > rect.top, rect.right > rect.left else { return ((0, 0, 0, 0), [], bounds) }
        }
        let w = rect.right - rect.left, h = rect.bottom - rect.top
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            // Rows top down, origin at the rect's top-left.
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: CGFloat(-rect.left), y: CGFloat(-rect.top))
            context.setShouldAntialias(true)
            let whole = CGRect(x: rect.left, y: rect.top, width: w, height: h)
            // Each shape is drawn over the ones before it, so its cost is its own area and Core Graphics' coverage
            // blend does the combining: white over is combine (a + b − ab), black over subtract (a(1 − b)),
            // black over everything outside the shape intersect (ab), white difference exclude (a + b − 2ab).
            for (index, shape) in shapes.enumerated() {
                // A first subtraction or intersection starts from everything.
                if index == 0, shape.operation == 2 || shape.operation == 3 {
                    context.setFillColor(gray: 1, alpha: 1)
                    context.fill(whole)
                }
                context.setBlendMode([1, 2, 3].contains(shape.operation) ? .normal : .difference)
                context.setFillColor(gray: shape.operation == 2 || shape.operation == 3 ? 0 : 1, alpha: 1)
                if shape.operation == 3 { context.addRect(whole) }
                context.addPath(shape.path)
                context.fillPath(using: .evenOdd)
            }
        }
        if inverted { for i in pixels.indices { pixels[i] = 255 - pixels[i] } }
        return (rect, pixels, bounds)
    }

    /// The patterns that `PtFl` layers use, from the file's `Patt`/`Pat2`/`Pat3` blocks, by their unique
    /// ID, as straight RGBA. Patterns in a mode other than RGB, greyscale or indexed, or deeper than 8 bits,
    /// are left out. Used patterns over `maxPatternPixels` together throw `.unsupported`, so the file falls back.
    public static func patterns(_ layers: PSDLayers) throws -> [String: RGBAImage] {
        func used(_ nodes: [PSDNode]) -> Set<String> {
            nodes.reduce(into: []) { ids, node in
                switch node {
                case .group(let group): ids.formUnion(used(group.children))
                case .layer(let layer):
                    guard let data = layer.blocks["PtFl"], let settings = try? PSDDescriptor.versioned(data),
                          case .object(let reference)? = settings["Ptrn"], case .text(let id)? = reference["Idnt"] else { return }
                    ids.insert(id)
                }
            }
        }
        let wanted = used(layers.nodes)
        var out: [String: RGBAImage] = [:]
        guard !wanted.isEmpty else { return out }
        var budget = maxPatternPixels
        for key in ["Patt", "Pat2", "Pat3"] {
            guard let data = layers.globalBlocks[key] else { continue }
            var r = Cursor(bytes: [UInt8](data))
            while r.bytes.count - r.at >= 4 {
                let length = try r.int(4)
                let start = r.at
                guard length <= r.bytes.count - start else { throw OwnDecodeError.corrupt }
                var p = Cursor(bytes: Array(r.bytes[start..<start + length]))
                if let (id, image) = try pattern(&p, wanted: wanted, budget: &budget) { out[id] = image }
                r.at = min(r.bytes.count, start + (length + 3) & ~3)
            }
        }
        return out
    }

    // MARK: Patterns

    /// 16 MP across all used patterns: their RGBA stays under 64 MB, and the at most five planes one is
    /// read from under 80 MB, whatever the file claims.
    static let maxPatternPixels = 4096 * 4096

    /// One pattern: version, mode, height, width, name, ID, colour table (indexed), then its virtual
    /// memory array list: version 3, length, rect, channel count, then that many channels plus a user
    /// mask and a sheet mask, each flagged as written or not. Only the first four channels and the sheet
    /// mask are decoded; the others are skipped. Nil for one not in `wanted`, before its pixels are read.
    private static func pattern(_ r: inout Cursor, wanted: Set<String>, budget: inout Int) throws -> (String, RGBAImage)? {
        _ = try r.int(4)
        let mode = try r.int(4), height = try r.int(2), width = try r.int(2)
        try r.skip(try r.int(4) * 2)
        let id = String(decoding: try r.take(try r.int(1)), as: UTF8.self)
        guard wanted.contains(id) else { return nil }
        guard width * height <= budget else { throw OwnDecodeError.unsupported }
        budget -= width * height
        let table = mode == 2 ? Array(try r.take(768)) : []
        guard try r.int(4) == 3 else { throw OwnDecodeError.corrupt }
        try r.skip(4 + 16)
        let count = try r.int(4)
        guard count <= 64, width > 0, height > 0 else { throw OwnDecodeError.corrupt }
        var planes: [[UInt8]?] = []
        for c in 0..<count + 2 {
            guard try r.int(4) != 0 else { planes.append(nil); continue }
            let length = try r.int(4)
            guard length > 0, c < min(count, 4) || c == count + 1 else { try r.skip(length); planes.append(nil); continue }
            var c = Cursor(bytes: Array(try r.take(length)))
            let depth = try c.int(4)
            let top = try c.int(4), left = try c.int(4), bottom = try c.int(4), right = try c.int(4)
            _ = try c.int(2)
            let compression = try c.int(1)
            guard depth == 8 else { return nil }
            let w = right - left, h = bottom - top
            guard w == width, h == height else { throw OwnDecodeError.corrupt }
            planes.append(try plane(&c, width: w, height: h, compression: compression))
        }
        // Every plane came from the data, so one bounds width × height by the file's size.
        guard planes.contains(where: { $0 != nil }) else { throw OwnDecodeError.corrupt }
        let n = width * height
        func at(_ c: Int) -> [UInt8]? { c < planes.count ? planes[c] : nil }
        // Transparency: a fourth channel, else the sheet mask.
        let alpha = (mode == 3 ? at(3) : nil) ?? at(count + 1)
        var pixels = [UInt8](repeating: 255, count: n * 4)
        switch mode {
        case 3:
            guard let red = at(0), let green = at(1), let blue = at(2) else { throw OwnDecodeError.corrupt }
            for i in 0..<n { (pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2]) = (red[i], green[i], blue[i]) }
        case 1, 2:
            guard let index = at(0) else { throw OwnDecodeError.corrupt }
            for i in 0..<n {
                let v = Int(index[i])
                for c in 0..<3 { pixels[i * 4 + c] = mode == 1 ? index[i] : table[v * 3 + c] }
            }
        default:
            return nil
        }
        if let alpha { for i in 0..<n { pixels[i * 4 + 3] = alpha[i] } }
        return (id, RGBAImage(width: width, height: height, pixels: pixels))
    }

    /// A pattern channel's pixels: raw (0) or PackBits rows with 2-byte counts first (1).
    private static func plane(_ c: inout Cursor, width: Int, height: Int, compression: Int) throws -> [UInt8] {
        let left = c.bytes.count - c.at
        switch compression {
        case 0:
            guard width * height <= left else { throw OwnDecodeError.corrupt }
            return Array(try c.take(width * height))
        case 1:
            // PackBits makes at most 128 bytes of 2, so a row takes at least 2 × ⌈width / 128⌉ bytes after its count.
            guard height * (2 + (width + 127) / 128 * 2) <= left else { throw OwnDecodeError.corrupt }
            let counts = try (0..<height).map { _ in try c.int(2) }
            var out = [UInt8](repeating: 0, count: width * height)
            try out.withUnsafeMutableBufferPointer { buffer in
                for (y, n) in counts.enumerated() {
                    let row = try c.take(n)
                    try row.withUnsafeBufferPointer {
                        try PSDComposite.unpackBits($0, width: width, into: UnsafeMutableBufferPointer(rebasing: buffer[y * width ..< (y + 1) * width]))
                    }
                }
            }
            return out
        default:
            throw OwnDecodeError.corrupt
        }
    }

    /// Tiles the pattern from the canvas origin, shifted by its phase and sized by its scale.
    // shortcut: each pixel takes the pattern pixel under its centre, not the area mean; average when a fit decode shows moiré.
    private static func pattern(_ settings: PSDDescriptor, patterns: [String: RGBAImage], sx: Double, sy: Double) throws
        -> (Int, Int) -> (UInt8, UInt8, UInt8, UInt8) {
        guard case .object(let reference)? = settings["Ptrn"], case .text(let id)? = reference["Idnt"],
              let tile = patterns[id] else { throw OwnDecodeError.corrupt }
        let size = max(number(settings["Scl "]) ?? 100, 1) / 100
        var phase = (x: 0.0, y: 0.0)
        if case .object(let point)? = settings["phase"] { phase = (number(point["Hrzn"]) ?? 0, number(point["Vrtc"]) ?? 0) }
        return { x, y in
            func wrap(_ v: Double, _ n: Int) -> Int { ((Int(v.rounded(.down)) % n) + n) % n }
            let u = wrap(((Double(x) + 0.5) / sx - phase.x) / size, tile.width)
            let v = wrap(((Double(y) + 0.5) / sy - phase.y) / size, tile.height)
            let o = (v * tile.width + u) * 4
            return (tile.pixels[o], tile.pixels[o + 1], tile.pixels[o + 2], tile.pixels[o + 3])
        }
    }

    // MARK: Gradients

    /// A gradient across `box`: its centre (moved by the offset, in percent of the box) and the angle
    /// (counter-clockwise from pointing right) give the gradient's line, whose length at 100 % scale is the
    /// box's extent along it; the first stop sits at the line's start. Colour and transparency stops are
    /// interpolated in RGB, each midpoint (on the later stop) where the two meet half-way.
    // shortcut: gradient dither is off, add noise if banding shows.
    // shortcut: smoothness (Intr) is ignored, colour changes linearly between stops; ease it if the corpus oracle shows the curve.
    private static func gradient(_ settings: PSDDescriptor, box: PSDRect) throws -> (Int, Int) -> (UInt8, UInt8, UInt8, UInt8) {
        guard case .object(let grad)? = settings["Grad"] else { throw OwnDecodeError.corrupt }
        let table = try gradientTable(grad)
        let angle = (number(settings["Angl"]) ?? 90) * .pi / 180
        let (cosA, sinA) = (cos(angle), sin(angle))
        let bw = Double(box.right - box.left), bh = Double(box.bottom - box.top)
        var offset = (x: 0.0, y: 0.0)
        if case .object(let point)? = settings["Ofst"] { offset = (number(point["Hrzn"]) ?? 0, number(point["Vrtc"]) ?? 0) }
        let cx = Double(box.left) + bw / 2 + offset.x / 100 * bw, cy = Double(box.top) + bh / 2 + offset.y / 100 * bh
        let half = max((abs(bw * cosA) + abs(bh * sinA)) / 2 * (number(settings["Scl "]) ?? 100) / 100, 1e-6)
        let reverse = settings["Rvrs"] == .bool(true)
        var type = "Lnr "
        if case .enumerated(_, let value)? = settings["Type"] { type = value }
        return { x, y in
            // Along the line and across it; y grows downwards on screen, so the line points (cos, −sin).
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            let along = dx * cosA - dy * sinA, across = dx * sinA + dy * cosA
            var t: Double
            switch type {
            case "Rdl ": t = (dx * dx + dy * dy).squareRoot() / half
            case "Rflc": t = abs(along) / half
            case "Dmnd": t = (abs(along) + abs(across)) / half
            case "Angl":
                let turn = (atan2(-dy, dx) - angle) / (2 * .pi)
                t = turn - turn.rounded(.down)
            default: t = (along / half + 1) / 2
            }
            if reverse { t = 1 - t }
            let o = Int((min(max(t, 0), 1) * Double(table.count / 4 - 1)).rounded()) * 4
            return (table[o], table[o + 1], table[o + 2], table[o + 3])
        }
    }

    /// The gradient's RGBA at 1,024 even steps from its start to its end.
    // shortcut: a noise gradient (ClNs) is one solid colour, the middle of its RGB ranges; draw the noise if a file shows it.
    private static func gradientTable(_ grad: PSDDescriptor) throws -> [UInt8] {
        let steps = 1024
        if case .enumerated(_, "ClNs")? = grad["GrdF"] {
            var c: [UInt8] = [128, 128, 128]
            if case .list(let low)? = grad["Mnm "], case .list(let high)? = grad["Mxm "], low.count >= 3, high.count >= 3,
               grad["ClrS"] == .enumerated(type: "ClrS", value: "RGBC") {
                c = (0..<3).map { UInt8(min(max(((number(low[$0]) ?? 0) + (number(high[$0]) ?? 0)) / 2 * 2.55, 0), 255).rounded()) }
            }
            return (0..<steps).flatMap { _ in c + [255] }
        }
        typealias Stop = (location: Double, midpoint: Double, value: [Double])
        func stops(_ key: String, _ value: (PSDDescriptor) throws -> [Double]) throws -> [Stop] {
            guard case .list(let list)? = grad[key] else { return [] }
            return try list.map {
                guard case .object(let stop) = $0 else { throw OwnDecodeError.corrupt }
                return ((number(stop["Lctn"]) ?? 0) / 4096, (number(stop["Mdpn"]) ?? 50) / 100, try value(stop))
            }.sorted { $0.location < $1.location }
        }
        let colours = try stops("Clrs") { stop in
            if stop["Clr "] == nil, case .enumerated(_, "BckC")? = stop["Type"] { return [255, 255, 255] }  // default background
            if stop["Clr "] == nil { return [0, 0, 0] }  // default foreground
            let c = try colour(stop["Clr "])
            return [Double(c.0), Double(c.1), Double(c.2)]
        }
        let opacities = try stops("Trns") { [min(max((number($0["Opct"]) ?? 100) * 2.55, 0), 255)] }
        func at(_ stops: [Stop], _ t: Double, _ fallback: [Double]) -> [Double] {
            guard let first = stops.first, let last = stops.last else { return fallback }
            if t <= first.location { return first.value }
            if t >= last.location { return last.value }
            let k = stops.firstIndex { $0.location > t }!
            let a = stops[k - 1], b = stops[k]
            var u = b.location > a.location ? (t - a.location) / (b.location - a.location) : 1
            let m = min(max(b.midpoint, 0.001), 0.999)
            u = u < m ? u / m / 2 : 0.5 + (u - m) / (1 - m) / 2
            return zip(a.value, b.value).map { $0 + ($1 - $0) * u }
        }
        return (0..<steps).flatMap { i -> [UInt8] in
            let t = Double(i) / Double(steps - 1)
            return (at(colours, t, [0, 0, 0]) + at(opacities, t, [255])).map { UInt8(min(max($0, 0), 255).rounded()) }
        }
    }

    // MARK: Values

    /// Clamped to ±10⁷ (well past any pixel count, percent or angle a file holds), so products of a few
    /// numbers stay finite and every conversion to an integer fits.
    static func number(_ value: PSDValue?) -> Double? {
        let d: Double
        switch value {
        case .double(let v)?, .unit(_, let v)?: d = v
        case .int(let n)?: d = Double(n)
        default: return nil
        }
        return min(max(d, -1e7), 1e7)
    }

    /// An RGB, HSB, greyscale or CMYK colour object as 8-bit RGB.
    // shortcut: Lab and book colours throw, so the file falls back to ImageIO; convert them when a file shows one.
    static func colour(_ value: PSDValue?) throws -> (UInt8, UInt8, UInt8) {
        guard case .object(let c)? = value else { throw OwnDecodeError.corrupt }
        func v(_ key: String) throws -> Double {
            guard let n = number(c[key]) else { throw OwnDecodeError.corrupt }
            return n
        }
        let rgb: (Double, Double, Double)
        switch c.classID {
        case "RGBC":
            if c["redFloat"] != nil {
                rgb = (try v("redFloat") * 255, try v("greenFloat") * 255, try v("blueFloat") * 255)
            } else {
                rgb = (try v("Rd  "), try v("Grn "), try v("Bl  "))
            }
        case "HSBC":
            let h = (try v("H   ") / 60).truncatingRemainder(dividingBy: 6), s = try v("Strt") / 100, b = try v("Brgh") / 100 * 255
            let hh = h < 0 ? h + 6 : h
            let f = hh - hh.rounded(.down), p = b * (1 - s), q = b * (1 - s * f), t = b * (1 - s * (1 - f))
            switch Int(hh) {
            case 0: rgb = (b, t, p)
            case 1: rgb = (q, b, p)
            case 2: rgb = (p, b, t)
            case 3: rgb = (p, q, b)
            case 4: rgb = (t, p, b)
            default: rgb = (b, p, q)
            }
        case "Grsc":
            let g = (1 - (try v("Gry ")) / 100) * 255
            rgb = (g, g, g)
        case "CMYC":
            // shortcut: CMYK through the naive formula, not the file's CMYK profile; use ColorSync if colours look off.
            let k = 1 - (try v("Blck")) / 100
            rgb = ((1 - (try v("Cyn ")) / 100) * k * 255, (1 - (try v("Mgnt")) / 100) * k * 255, (1 - (try v("Ylw ")) / 100) * k * 255)
        default:
            throw OwnDecodeError.corrupt
        }
        func byte(_ d: Double) -> UInt8 { UInt8(min(max(d, 0), 255).rounded()) }
        return (byte(rgb.0), byte(rgb.1), byte(rgb.2))
    }

    /// Big-endian reads over bytes; every read past the end throws `.corrupt`.
    private struct Cursor {
        let bytes: [UInt8]
        var at = 0

        mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, n <= bytes.count - at else { throw OwnDecodeError.corrupt }
            defer { at += n }
            return bytes[at..<at + n]
        }
        mutating func int(_ n: Int) throws -> Int { try take(n).reduce(0) { $0 << 8 | Int($1) } }
        mutating func skip(_ n: Int) throws { _ = try take(n) }
    }
}
