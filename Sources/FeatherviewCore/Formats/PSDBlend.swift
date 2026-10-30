import Foundation

/// Photoshop's blend modes: the per-pixel formulas on colours in 0…1, and compositing an 8-bit layer onto
/// a canvas with one of them. Separable and non-separable formulas follow W3C Compositing and Blending
/// Level 1; the Photoshop-only modes follow their published definitions.
public enum PSDBlend {
    public enum Mode: CaseIterable, Sendable {
        case normal, dissolve, darken, multiply, colorBurn, linearBurn, darkerColor, lighten, screen, colorDodge,
             linearDodge, lighterColor, overlay, softLight, hardLight, vividLight, linearLight, pinLight, hardMix,
             difference, exclusion, subtract, divide, hue, saturation, color, luminosity
    }

    private static let keys: [String: Mode] = [
        "norm": .normal, "diss": .dissolve, "dark": .darken, "mul ": .multiply, "idiv": .colorBurn,
        "lbrn": .linearBurn, "dkCl": .darkerColor, "lite": .lighten, "scrn": .screen, "div ": .colorDodge,
        "lddg": .linearDodge, "lgCl": .lighterColor, "over": .overlay, "sLit": .softLight, "hLit": .hardLight,
        "vLit": .vividLight, "lLit": .linearLight, "pLit": .pinLight, "hMix": .hardMix, "diff": .difference,
        "smud": .exclusion, "fsub": .subtract, "fdiv": .divide, "hue ": .hue, "sat ": .saturation,
        "colr": .color, "lum ": .luminosity,
    ]

    /// The mode for a layer record's blend key; nil for `pass` (a group's pass-through) and unknown keys.
    public static func mode(_ key: String) -> Mode? { keys[key] }

    /// B(Cb, Cs): the colour the mode makes from the backdrop and the source, both opaque.
    public static func blend(_ mode: Mode, backdrop b: SIMD3<Float>, source s: SIMD3<Float>) -> SIMD3<Float> {
        switch mode {
        case .normal, .dissolve: return s
        case .darken: return pointwiseMin(b, s)
        case .lighten: return pointwiseMax(b, s)
        case .multiply: return b * s
        case .screen: return b + s - b * s
        case .colorBurn: return each(b, s, colorBurn)
        case .linearBurn: return clamp01(b + s - 1)
        case .colorDodge: return each(b, s, colorDodge)
        case .linearDodge: return clamp01(b + s)
        case .overlay: return each(b, s) { b, s in hardLight(s, b) }
        case .hardLight: return each(b, s, hardLight)
        case .softLight: return each(b, s, softLight)
        case .vividLight: return each(b, s) { b, s in s <= 0.5 ? colorBurn(b, 2 * s) : colorDodge(b, 2 * s - 1) }
        case .linearLight: return clamp01(b + 2 * s - 1)
        case .pinLight: return each(b, s) { b, s in s <= 0.5 ? min(b, 2 * s) : max(b, 2 * s - 1) }
        case .hardMix: return each(b, s) { b, s in b + s >= 1 ? 1 : 0 }
        case .difference: return pointwiseMax(b, s) - pointwiseMin(b, s)
        case .exclusion: return b + s - 2 * b * s
        case .subtract: return clamp01(b - s)
        case .divide: return each(b, s) { b, s in s > 0 ? min(1, b / s) : (b > 0 ? 1 : 0) }
        case .darkerColor: return lum(s) < lum(b) ? s : b
        case .lighterColor: return lum(s) > lum(b) ? s : b
        case .hue: return setLum(setSat(s, sat(b)), lum(b))
        case .saturation: return setLum(setSat(b, sat(s)), lum(b))
        case .color: return setLum(s, lum(b))
        case .luminosity: return setLum(b, lum(s))
        }
    }

    /// Draws `layer` (straight alpha) onto `canvas` with its top-left corner at `at`, which may be negative
    /// or past the edge; only the overlap changes. `alpha` is a layer-sized mask (0…255) multiplying the
    /// layer's alpha; `opacity` and `fill` (0…1, taken to 1/255 steps as Photoshop stores them) multiply it too.
    /// W3C source-over with the mixing step Cs' = (1 − αb)·Cs + αb·B(Cb, Cs), straight alpha out, rounded half
    /// up. Dissolve takes a pixel fully or not at all, with probability α, from a hash of its canvas (x, y), so
    /// a decode is repeatable. Integer maths throughout; only the modes without one compute B in floats.
    // shortcut: fill multiplies alpha like opacity in every mode, apply it inside the blend for the eight special modes (colour/linear burn, colour/linear dodge, vivid/linear light, hard mix, difference) if the corpus check against Photoshop's composites shows that.
    public static func composite(_ mode: Mode, onto canvas: inout RGBAImage, layer: RGBAImage, at origin: (x: Int, y: Int),
                                 alpha mask: [UInt8]? = nil, opacity: Float = 1, fill: Float = 1) {
        // Opacity · fill in 0…255²; a pixel's alpha is srcA · mask · k / 255², rounded, in 0…255².
        let k = Int((min(max(opacity, 0), 1) * 255).rounded()) * Int((min(max(fill, 0), 1) * 255).rounded())
        let x0 = max(origin.x, 0), x1 = min(origin.x + layer.width, canvas.width)
        let y0 = max(origin.y, 0), y1 = min(origin.y + layer.height, canvas.height)
        guard k > 0, x0 < x1, y0 < y1 else { return }
        precondition(mask.map { $0.count == layer.width * layer.height } ?? true, "mask size")
        let columns = x0..<x1
        // Rows in bands on all cores once a layer is large enough to pay for it.
        let bands = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, columns.count * (y1 - y0) / 65_536))
        layer.pixels.withUnsafeBufferPointer { src in
            canvas.pixels.withUnsafeMutableBufferPointer { dst in
                (mask ?? []).withUnsafeBufferPointer { maskBuffer in
                    // Each band writes only its own canvas rows; the layer and mask are only read.
                    nonisolated(unsafe) let sp = src.baseAddress!, dp = dst.baseAddress!
                    nonisolated(unsafe) let mp = mask == nil ? nil : maskBuffer.baseAddress  // as above
                    let canvasWidth = canvas.width, layerWidth = layer.width
                    DispatchQueue.concurrentPerform(iterations: bands) { band in
                        let rows = y0 + band * (y1 - y0) / bands ..< y0 + (band + 1) * (y1 - y0) / bands
                        let p = Planes(src: sp, dst: dp, mask: mp, layerWidth: layerWidth, canvasWidth: canvasWidth, origin: origin)
                        switch mode {
                        case .normal, .dissolve: run(mode, p, k, columns, rows) { _, s in s }
                        case .darken: run(mode, p, k, columns, rows) { b, s in min(b, s) }
                        case .lighten: run(mode, p, k, columns, rows) { b, s in max(b, s) }
                        case .multiply: run(mode, p, k, columns, rows) { b, s in mul(b, s) }
                        case .screen: run(mode, p, k, columns, rows) { b, s in b &+ s &- mul(b, s) }
                        case .linearBurn: run(mode, p, k, columns, rows) { b, s in max(b &+ s, 255) &- 255 }
                        case .linearDodge: run(mode, p, k, columns, rows) { b, s in min(b &+ s, 255) }
                        case .difference: run(mode, p, k, columns, rows) { b, s in max(b, s) &- min(b, s) }
                        case .exclusion: run(mode, p, k, columns, rows) { b, s in b &+ s &- 2 &* mul(b, s) }
                        case .subtract: run(mode, p, k, columns, rows) { b, s in max(b, s) &- s }
                        default: run(mode, p, k, columns, rows, separable: nil)
                        }
                    }
                }
            }
        }
    }

    /// b · s / 255, rounded, on 0…255.
    @inline(__always) private static func mul(_ b: UInt32, _ s: UInt32) -> UInt32 { (b &* s &+ 127) / 255 }

    /// The layer's pixels, the canvas's and the mask (layer-sized, nil for none), with where the layer sits.
    private struct Planes {
        let src: UnsafePointer<UInt8>, dst: UnsafeMutablePointer<UInt8>, mask: UnsafePointer<UInt8>?
        let layerWidth: Int, canvasWidth: Int, origin: (x: Int, y: Int)
    }

    /// The compositing loop for one mode over `rows`: `separable` is B per channel on 0…255, nil for B in floats.
    /// Wrapping integer maths whose values stay below 2³²; αs in 0…255². Over an opaque backdrop, the usual case,
    /// αo is 1 and the divisors are constants; an opaque run in normal mode is copied as it is.
    @inline(__always)
    private static func run(_ mode: Mode, _ planes: Planes, _ k: Int, _ columns: Range<Int>, _ rows: Range<Int>,
                            separable: ((UInt32, UInt32) -> UInt32)?) {
        let canvasWidth = planes.canvasWidth, layerWidth = planes.layerWidth, count = columns.count, origin = planes.origin
        let sp = planes.src, dp = planes.dst, mask = planes.mask
        // Not dissolve: a taken pixel there is drawn at alpha 255, not the layer's own alpha the copy would keep.
        let copies = mode == .normal
        // Source alphas worked out a row ahead, unless they are just the layer's own (no mask, full opacity).
        let table = mask != nil || mode == .dissolve || k != 65_025
        var alphas = [UInt32](repeating: 0, count: table ? count : 0)
        alphas.withUnsafeMutableBufferPointer { alphas in
            let ap = table ? alphas.baseAddress : nil
            for row in rows {
                let m0 = (row - origin.y) * layerWidth + (columns.lowerBound - origin.x)
                let s0 = m0 * 4, d0 = (row * canvasWidth + columns.lowerBound) * 4
                if let ap {
                    if let mask {
                        for i in 0..<count {
                            let a = UInt64(sp[s0 + i * 4 + 3]) &* UInt64(mask[m0 + i]) &* UInt64(k)
                            ap[i] = UInt32(truncatingIfNeeded: (a &+ 32_512) / 65_025)
                        }
                    } else {
                        let k = UInt32(k)
                        for i in 0..<count { ap[i] = (UInt32(sp[s0 + i * 4 + 3]) &* k &+ 127) / 255 }
                    }
                    if mode == .dissolve {
                        for i in 0..<count { ap[i] = unitHash(columns.lowerBound + i, row) * 65_025 < Float(ap[i]) ? 65_025 : 0 }
                    }
                }
                var i = 0
                while i < count {
                    let s = s0 + i * 4, d = d0 + i * 4
                    let aS = table ? ap.unsafelyUnwrapped[i] : UInt32(sp[s + 3]) &* 255
                    i += 1
                    if aS == 0 { continue }
                    if copies && aS == 65_025 {
                        var end = i
                        if table {
                            while end < count && ap.unsafelyUnwrapped[end] == 65_025 { end += 1 }
                        } else {
                            while end < count && sp[s0 + end * 4 + 3] == 255 { end += 1 }
                        }
                        UnsafeMutableRawPointer(dp + d).copyMemory(from: sp + s, byteCount: (end - i + 1) * 4)
                        i = end
                        continue
                    }
                    let aB = UInt32(dp[d + 3])
                    if aB == 0 {
                        dp[d] = sp[s]; dp[d + 1] = sp[s + 1]; dp[d + 2] = sp[s + 2]
                        dp[d + 3] = UInt8(truncatingIfNeeded: (aS &+ 127) / 255)
                        continue
                    }
                    // B per channel, on 0…255.
                    var f = (UInt32(sp[s]), UInt32(sp[s + 1]), UInt32(sp[s + 2]))
                    let b = (UInt32(dp[d]), UInt32(dp[d + 1]), UInt32(dp[d + 2]))
                    if let separable {
                        f = (separable(b.0, f.0), separable(b.1, f.1), separable(b.2, f.2))
                    } else {
                        let x = blend(mode, backdrop: SIMD3(Float(b.0), Float(b.1), Float(b.2)) / 255,
                                      source: SIMD3(Float(f.0), Float(f.1), Float(f.2)) / 255)
                        f = (UInt32(byte(x.x)), UInt32(byte(x.y)), UInt32(byte(x.z)))
                    }
                    if aB == 255 {
                        // Co = αs·B + (1 − αs)·Cb.
                        let rest = 65_025 &- aS
                        func out(_ f: UInt32, _ b: UInt32) -> UInt8 {
                            UInt8(truncatingIfNeeded: (aS &* f &+ rest &* b &+ 32_512) / 65_025)
                        }
                        dp[d] = out(f.0, b.0); dp[d + 1] = out(f.1, b.1); dp[d + 2] = out(f.2, b.2)
                        continue
                    }
                    // Cs' in 0…255², αo in 0…255³, the colours times αo below 255⁴ (in 64 bits); Co is their quotient.
                    let c = (UInt32(sp[s]), UInt32(sp[s + 1]), UInt32(sp[s + 2]))
                    let aO = UInt64(aS &* 255 &+ aB &* (65_025 &- aS)), rest = UInt64((65_025 &- aS) &* aB)
                    func out(_ c: UInt32, _ f: UInt32, _ b: UInt32) -> UInt8 {
                        let mixed = UInt64((255 &- aB) &* c &+ aB &* f)
                        return UInt8(truncatingIfNeeded: (UInt64(aS) &* mixed &+ rest &* UInt64(b) &+ aO / 2) / aO)
                    }
                    dp[d] = out(c.0, f.0, b.0); dp[d + 1] = out(c.1, f.1, b.1); dp[d + 2] = out(c.2, f.2, b.2)
                    dp[d + 3] = UInt8(truncatingIfNeeded: (aO &+ 32_512) / 65_025)
                }
            }
        }
    }

    private static func byte(_ v: Float) -> UInt8 { v.isNaN ? 0 : UInt8(min(max(v, 0), 1) * 255 + 0.5) }

    /// A value in 0..<1 from (x, y), the same on every run.
    private static func unitHash(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1 ^ UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77
        h ^= h >> 16; h &*= 0x7FEB_352D; h ^= h >> 15; h &*= 0x846C_A68B; h ^= h >> 16
        return Float(h >> 8) / Float(1 << 24)
    }

    private static func each(_ b: SIMD3<Float>, _ s: SIMD3<Float>, _ f: (Float, Float) -> Float) -> SIMD3<Float> {
        SIMD3(f(b.x, s.x), f(b.y, s.y), f(b.z, s.z))
    }

    private static func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> { v.clamped(lowerBound: .zero, upperBound: .one) }

    private static func colorBurn(_ b: Float, _ s: Float) -> Float {
        b >= 1 ? 1 : s <= 0 ? 0 : 1 - min(1, (1 - b) / s)
    }

    private static func colorDodge(_ b: Float, _ s: Float) -> Float {
        b <= 0 ? 0 : s >= 1 ? 1 : min(1, b / (1 - s))
    }

    private static func hardLight(_ b: Float, _ s: Float) -> Float {
        s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1)
    }

    private static func softLight(_ b: Float, _ s: Float) -> Float {
        if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
        let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
        return b + (2 * s - 1) * (d - b)
    }

    private static func lum(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }

    private static func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
        let c = c + (l - lum(c))
        let l = lum(c), n = c.min(), x = c.max()
        var out = c
        // A grey a rounding step outside 0…1 has l == n (or x); clamping later handles it, dividing gives 0/0.
        if n < 0, l > n { out = l + (out - l) * l / (l - n) }
        if x > 1, x > l { out = l + (out - l) * (1 - l) / (x - l) }
        return out
    }

    private static func sat(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }

    private static func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let lo = c.min(), hi = c.max()
        guard hi > lo else { return .zero }
        return (c - lo) * s / (hi - lo)
    }
}
