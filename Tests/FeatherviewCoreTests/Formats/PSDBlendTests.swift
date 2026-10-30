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

    @Test func dissolveTakesAPixelAtFullAlpha() {
        let layer = RGBAImage(width: 64, height: 1, pixels: [UInt8]((0..<64).flatMap { _ in [255, 0, 0, 128] as [UInt8] }))
        var opaque = RGBAImage(width: 64, height: 1)
        PSDBlend.composite(.dissolve, onto: &opaque, layer: layer, at: (x: 0, y: 0))
        #expect(stride(from: 3, to: opaque.pixels.count, by: 4).allSatisfy { opaque.pixels[$0] == 255 })
        var clear = RGBAImage(width: 64, height: 1, pixels: [UInt8](repeating: 0, count: 256))
        PSDBlend.composite(.dissolve, onto: &clear, layer: layer, at: (x: 0, y: 0))
        let alphas = Set(stride(from: 3, to: clear.pixels.count, by: 4).map { clear.pixels[$0] })
        #expect(alphas == [0, 255])
    }

    @Test func colorModeOnGreysNeverTraps() {
        for b in 0...255 {
            for s in 0...255 {
                let x = blend(.color, (Float(b) / 255, Float(b) / 255, Float(b) / 255), (Float(s) / 255, Float(s) / 255, Float(s) / 255))
                #expect(!x.x.isNaN && !x.y.isNaN && !x.z.isNaN, "backdrop \(b), source \(s)")
            }
        }
        var canvas = RGBAImage(width: 1, height: 1)
        PSDBlend.composite(.color, onto: &canvas, layer: RGBAImage(width: 1, height: 1, pixels: [29, 29, 29, 255]), at: (x: 0, y: 0))
        #expect(canvas.pixels == [0, 0, 0, 255])
    }

    /// Every mode through `composite` on random straight-alpha pixels, against the float formula: within 1 step.
    @Test func compositeMatchesTheFormula() {
        var rng = SystemRandomNumberGenerator()
        let n = 2_000
        let below = RGBAImage(width: n, height: 1, pixels: (0..<n * 4).map { i in
            i % 4 == 3 ? [0, 255, UInt8.random(in: 0...255, using: &rng)][(i / 4) % 3] : UInt8.random(in: 0...255, using: &rng)
        })
        let layer = RGBAImage(width: n, height: 1, pixels: (0..<n * 4).map { i in
            i % 4 == 3 ? [255, 0, UInt8.random(in: 0...255, using: &rng)][(i / 8) % 3] : UInt8.random(in: 0...255, using: &rng)
        })
        let mask = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
        for mode in PSDBlend.Mode.allCases where mode != .dissolve {
            for (alpha, opacity) in [(nil, Float(1)), (mask, Float(0.6))] as [([UInt8]?, Float)] {
                var canvas = below
                PSDBlend.composite(mode, onto: &canvas, layer: layer, at: (x: 0, y: 0), alpha: alpha, opacity: opacity, fill: 1)
                for p in 0..<n {
                    let d = p * 4
                    let aS = Float(layer.pixels[d + 3]) / 255 * (Float(opacity * 255).rounded() / 255)
                        * Float(alpha?[p] ?? 255) / 255
                    let aB = Float(below.pixels[d + 3]) / 255
                    let cS = SIMD3(Float(layer.pixels[d]), Float(layer.pixels[d + 1]), Float(layer.pixels[d + 2])) / 255
                    let cB = SIMD3(Float(below.pixels[d]), Float(below.pixels[d + 1]), Float(below.pixels[d + 2])) / 255
                    let mixed = (1 - aB) * cS + aB * PSDBlend.blend(mode, backdrop: cB, source: cS)
                    let aO = aS + aB * (1 - aS)
                    let cO = aO > 0 ? (aS * mixed + (1 - aS) * aB * cB) / aO : cB
                    let want = [cO.x, cO.y, cO.z, aO].map { Int(min(max($0, 0), 1) * 255 + 0.5) }
                    let got = (0..<4).map { Int(canvas.pixels[d + $0]) }
                    // A pixel the layer leaves out keeps its colour; with nothing left of either, colour does not count.
                    let channels = aO * 255 < 0.5 ? 3..<4 : 0..<4
                    #expect(channels.allSatisfy { abs(got[$0] - want[$0]) <= 1 },
                            "\(mode) pixel \(p): \(got) want \(want), below \(below.pixels[d..<d + 4]) layer \(layer.pixels[d..<d + 4])")
                    if channels.contains(where: { abs(got[$0] - want[$0]) > 1 }) { break }
                }
            }
        }
    }

    /// Task 7's budget: a 12 MP layered PSD with 30 layers < 500 ms, about 16 ms a layer in a release build, which
    /// an opaque normal layer meets (measured ~9 ms; translucent normal ~35 ms, multiply ~55 ms, so those are only
    /// guarded against regressions). Unoptimized the loops are many times slower, so a debug build times 1/16 of it.
    @Test func compositeIsFastEnoughFor30Layers() {
        let debug = _isDebugAssertConfiguration()
        let width = debug ? 1000 : 4000, height = debug ? 750 : 3000
        var opaque = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: opaque.count, by: 4) {
            opaque[i] = UInt8(truncatingIfNeeded: i); opaque[i + 1] = UInt8(truncatingIfNeeded: i >> 8)
            opaque[i + 2] = UInt8(truncatingIfNeeded: i >> 3); opaque[i + 3] = 255
        }
        let layer = RGBAImage(width: width, height: height, pixels: opaque)
        var canvas = RGBAImage(width: width, height: height, pixels: opaque.reversed())
        for (mode, opacity, limit) in [(PSDBlend.Mode.normal, Float(1), debug ? 100 : 16), (.normal, 0.5, debug ? 1000 : 80),
                                       (.multiply, 1, debug ? 1000 : 80)] {
            var elapsed = Duration.seconds(10)
            for _ in 0..<3 {
                let start = ContinuousClock.now
                PSDBlend.composite(mode, onto: &canvas, layer: layer, at: (x: 0, y: 0), alpha: nil, opacity: opacity, fill: 1)
                elapsed = min(elapsed, ContinuousClock.now - start)
            }
            #expect(elapsed < .milliseconds(limit), "\(mode) \(opacity) took \(elapsed)")
        }
    }
}
