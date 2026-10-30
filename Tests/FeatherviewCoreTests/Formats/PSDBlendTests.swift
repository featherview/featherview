import Testing
@testable import FeatherviewCore

infix operator ≈: ComparisonPrecedence

private func ≈ (lhs: SIMD3<Float>, rhs: (Float, Float, Float)) -> Bool {
    abs(lhs.x - rhs.0) < 0.001 && abs(lhs.y - rhs.1) < 0.001 && abs(lhs.z - rhs.2) < 0.001
}

private func blend(_ mode: PSDBlend.Mode, _ b: (Float, Float, Float), _ s: (Float, Float, Float)) -> SIMD3<Float> {
    PSDBlend.blend(mode, backdrop: SIMD3(b.0, b.1, b.2), source: SIMD3(s.0, s.1, s.2))
}

struct PSDBlendTests {
    @Test func separableModes() {
        let b = SIMD3<Float>(0.2, 0.5, 0.8), s = SIMD3<Float>(0.6, 0.5, 0.1)
        #expect(PSDBlend.blend(.multiply, backdrop: b, source: s) ≈ (0.12, 0.25, 0.08))
        #expect(PSDBlend.blend(.screen, backdrop: b, source: s) ≈ (0.68, 0.75, 0.82))
        #expect(PSDBlend.blend(.linearBurn, backdrop: b, source: s) ≈ (0, 0, 0))
        #expect(PSDBlend.blend(.subtract, backdrop: b, source: s) ≈ (0, 0, 0.7))
        #expect(PSDBlend.blend(.difference, backdrop: b, source: s) ≈ (0.4, 0, 0.7))

        #expect(blend(.normal, (0.2, 0.5, 1), (0.6, 0, 0.3)) ≈ (0.6, 0, 0.3))
        #expect(blend(.dissolve, (0.2, 0.5, 1), (0.6, 0, 0.3)) ≈ (0.6, 0, 0.3))
        #expect(blend(.darken, (0.2, 0.5, 1), (0.6, 0, 0.3)) ≈ (0.2, 0, 0.3))
        #expect(blend(.lighten, (0.2, 0.5, 1), (0.6, 0, 0.3)) ≈ (0.6, 0.5, 1))
        #expect(blend(.colorBurn, (1, 0.5, 0.6), (0.3, 0, 0.8)) ≈ (1, 0, 0.5))
        #expect(blend(.colorDodge, (0, 0.5, 0.2), (0.5, 1, 0.6)) ≈ (0, 1, 0.5))
        #expect(blend(.linearDodge, (0.2, 0.5, 0.8), (0.6, 0.5, 0.1)) ≈ (0.8, 1, 0.9))
        #expect(blend(.overlay, (0.25, 0.75, 1), (0.4, 0.2, 0.2)) ≈ (0.2, 0.6, 1))
        #expect(blend(.hardLight, (0.4, 0.2, 0), (0.25, 0.75, 1)) ≈ (0.2, 0.6, 1))
        #expect(blend(.softLight, (0.25, 0.64, 1), (0.25, 1, 0)) ≈ (0.15625, 0.8, 1))
        #expect(blend(.vividLight, (0.6, 0.2, 0.5), (0.25, 0.75, 0)) ≈ (0.2, 0.4, 0))
        #expect(blend(.linearLight, (0.2, 0.5, 0.8), (0.6, 0.5, 1)) ≈ (0.4, 0.5, 1))
        #expect(blend(.pinLight, (0.2, 0.5, 0.8), (0.25, 0.9, 1)) ≈ (0.2, 0.8, 1))
        #expect(blend(.hardMix, (0.2, 0.5, 0.8), (0.9, 0.4, 1)) ≈ (1, 0, 1))
        #expect(blend(.exclusion, (0.2, 0.5, 1), (0.6, 0.5, 0.3)) ≈ (0.56, 0.5, 0.7))
        #expect(blend(.divide, (0.2, 0.5, 0), (0.4, 0.25, 0)) ≈ (0.5, 1, 0))
        #expect(blend(.divide, (0.3, 0, 1), (0, 0.5, 1)) ≈ (1, 0, 1))
    }

    @Test func nonSeparableModes() {
        let s = (Float(0.2), Float(0.5), Float(0.8)), b = (Float(0.6), Float(0.5), Float(0.1))
        #expect(blend(.hue, b, s) ≈ (0.2835, 0.5335, 0.7835))
        #expect(blend(.saturation, b, s) ≈ (0.6228, 0.5028, 0.0228))
        #expect(blend(.color, b, s) ≈ (0.243, 0.543, 0.843))
        #expect(blend(.luminosity, b, s) ≈ (0.557, 0.457, 0.057))
        // Luminosity 0.443 for the source, 0.486 for the backdrop.
        #expect(blend(.darkerColor, b, s) ≈ s)
        #expect(blend(.lighterColor, b, s) ≈ b)
        // SetLum clips a colour pushed past white back into range, keeping its luminosity.
        #expect(blend(.luminosity, (1, 0, 0), (1, 1, 1)) ≈ (1, 1, 1))
    }

    @Test func keysRoundTrip() {
        let keys = ["norm", "diss", "dark", "mul ", "idiv", "lbrn", "dkCl", "lite", "scrn", "div ",
                    "lddg", "lgCl", "over", "sLit", "hLit", "vLit", "lLit", "pLit", "hMix", "diff",
                    "smud", "fsub", "fdiv", "hue ", "sat ", "colr", "lum "]
        let modes = keys.compactMap(PSDBlend.mode)
        #expect(modes.count == keys.count)
        #expect(Set(modes) == Set(PSDBlend.Mode.allCases))
        #expect(PSDBlend.mode("pass") == nil)
        #expect(PSDBlend.mode("zzzz") == nil)
    }

    @Test func compositeRespectsAlphaOpacityAndMask() {
        var canvas = RGBAImage(width: 2, height: 1)  // opaque black
        let layer = RGBAImage(width: 1, height: 1, pixels: [255, 255, 255, 128])
        PSDBlend.composite(.normal, onto: &canvas, layer: layer, at: (x: 1, y: 0), alpha: [128], opacity: 0.5, fill: 1)
        // α = 128/255 · 0.5 · 128/255 ≈ 0.126 → 32.
        #expect(canvas.pixels == [0, 0, 0, 255, 32, 32, 32, 255])

        var clear = RGBAImage(width: 1, height: 1, pixels: [10, 20, 30, 0])
        let source = RGBAImage(width: 1, height: 1, pixels: [200, 100, 50, 128])
        PSDBlend.composite(.multiply, onto: &clear, layer: source, at: (x: 0, y: 0), alpha: nil, opacity: 1, fill: 1)
        #expect(clear.pixels == [200, 100, 50, 128])

        // Layer partly outside the canvas: only the overlap changes.
        var small = RGBAImage(width: 1, height: 1)
        let wide = RGBAImage(width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 16))
        PSDBlend.composite(.screen, onto: &small, layer: wide, at: (x: -1, y: -1), alpha: nil, opacity: 1, fill: 1)
        #expect(small.pixels == [255, 255, 255, 255])
    }

    @Test func dissolveIsRepeatable() {
        let layer = RGBAImage(width: 100, height: 100,
                              pixels: [UInt8]((0..<10_000).flatMap { _ in [255, 0, 0, 128] as [UInt8] }))
        func run() -> RGBAImage {
            var canvas = RGBAImage(width: 100, height: 100)
            PSDBlend.composite(.dissolve, onto: &canvas, layer: layer, at: (x: 0, y: 0), alpha: nil, opacity: 1, fill: 1)
            return canvas
        }
        let first = run()
        #expect(first == run())
        let taken = stride(from: 0, to: first.pixels.count, by: 4).filter { first.pixels[$0] == 255 }.count
        let untouched = stride(from: 0, to: first.pixels.count, by: 4).filter { first.pixels[$0] == 0 }.count
        #expect(taken + untouched == 10_000)  // all or nothing per pixel
        #expect(abs(taken - 5_020) < 250)
    }
}
