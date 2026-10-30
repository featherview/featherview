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
    /// layer's alpha; `opacity` and `fill` (0…1) multiply it too. W3C source-over with the mixing step
    /// Cs' = (1 − αb)·Cs + αb·B(Cb, Cs), straight alpha out, rounded half up. Dissolve takes a pixel fully
    /// or not at all, with probability α, from a hash of its canvas (x, y), so a decode is repeatable.
    // shortcut: fill multiplies alpha like opacity in every mode, apply it inside the blend for the eight special modes (colour/linear burn, colour/linear dodge, vivid/linear light, hard mix, difference) if the corpus check against Photoshop's composites shows that.
    public static func composite(_ mode: Mode, onto canvas: inout RGBAImage, layer: RGBAImage, at origin: (x: Int, y: Int),
                                 alpha mask: [UInt8]? = nil, opacity: Float = 1, fill: Float = 1) {
        let scale = min(max(opacity, 0), 1) * min(max(fill, 0), 1) / 255
        let x0 = max(origin.x, 0), x1 = min(origin.x + layer.width, canvas.width)
        let y0 = max(origin.y, 0), y1 = min(origin.y + layer.height, canvas.height)
        guard scale > 0, x0 < x1, y0 < y1 else { return }
        precondition(mask.map { $0.count == layer.width * layer.height } ?? true, "mask size")
        let canvasWidth = canvas.width, layerWidth = layer.width
        layer.pixels.withUnsafeBufferPointer { src in
            canvas.pixels.withUnsafeMutableBufferPointer { dst in
                for row in y0..<y1 {
                    var m = (row - origin.y) * layerWidth + (x0 - origin.x)
                    var s = m * 4
                    var d = (row * canvasWidth + x0) * 4
                    for column in x0..<x1 {
                        defer { m += 1; s += 4; d += 4 }
                        var aS = Float(src[s + 3]) * scale
                        if let mask { aS *= Float(mask[m]) / 255 }
                        if mode == .dissolve { aS = unitHash(column, row) < aS ? 1 : 0 }
                        guard aS > 0 else { continue }
                        let cS = SIMD3(Float(src[s]), Float(src[s + 1]), Float(src[s + 2])) / 255
                        let aB = Float(dst[d + 3]) / 255
                        let cB = SIMD3(Float(dst[d]), Float(dst[d + 1]), Float(dst[d + 2])) / 255
                        let mixed = mode == .normal || mode == .dissolve || aB == 0
                            ? cS : (1 - aB) * cS + aB * blend(mode, backdrop: cB, source: cS)
                        let aO = aS + aB * (1 - aS)
                        let cO = (aS * mixed + (1 - aS) * aB * cB) / aO
                        dst[d] = byte(cO.x); dst[d + 1] = byte(cO.y); dst[d + 2] = byte(cO.z)
                        dst[d + 3] = byte(aO)
                    }
                }
            }
        }
    }

    private static func byte(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255 + 0.5) }

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
        if n < 0 { out = l + (out - l) * l / (l - n) }
        if x > 1 { out = l + (out - l) * (1 - l) / (x - l) }
        return out
    }

    private static func sat(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }

    private static func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let lo = c.min(), hi = c.max()
        guard hi > lo else { return .zero }
        return (c - lo) * s / (hi - lo)
    }
}
