import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDAdjustmentsTests {
    /// Builds a binary adjustment block (big-endian).
    struct Block {
        var data: [UInt8] = []
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u16(_ v: Int) { data += withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).bigEndian, Array.init) }
        mutating func u32(_ v: Int) { data += withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).bigEndian, Array.init) }
        mutating func f32(_ v: Float) { data += withUnsafeBytes(of: v.bitPattern.bigEndian, Array.init) }
    }

    /// A versioned descriptor block of `long` values plus any extra items written by `extra`.
    func descriptorBlock(_ ints: [(String, Int)], extraCount: Int = 0, extra: (inout PSDDescriptorTests.Bytes) -> Void = { _ in }) -> Data {
        var b = PSDDescriptorTests.Bytes()
        b.u32(16)
        b.header("null", count: ints.count + extraCount)
        for (key, value) in ints { b.id(key); b.os("long"); b.u32(UInt32(truncatingIfNeeded: value)) }
        extra(&b)
        return Data(b.data)
    }

    func adjust(_ key: String, _ data: Data, _ c: (Float, Float, Float)) throws -> SIMD3<Float> {
        let f = try #require(try PSDAdjustments.adjustment(key: key, data: data))
        var v = SIMD3<Float>(c.0, c.1, c.2)
        f(&v)
        return v
    }

    func close(_ v: SIMD3<Float>, _ c: (Float, Float, Float), _ tolerance: Float = 0.002) -> Bool {
        abs(v.x - c.0) <= tolerance && abs(v.y - c.1) <= tolerance && abs(v.z - c.2) <= tolerance
    }

    func lum(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }

    func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    @Test func invert() throws {
        #expect(close(try adjust("nvrt", Data(), (0.2, 0.5, 1)), (0.8, 0.5, 0)))
    }

    @Test func threshold() throws {
        var b = Block(); b.u16(128); b.u16(0)
        #expect(try adjust("thrs", Data(b.data), (127 / 255, 127 / 255, 127 / 255)) == .zero)
        #expect(try adjust("thrs", Data(b.data), (128 / 255, 128 / 255, 128 / 255)) == .one)
        // On luminosity: pure blue is dark, pure green is light.
        #expect(try adjust("thrs", Data(b.data), (0, 0, 1)) == .zero)
        #expect(try adjust("thrs", Data(b.data), (0, 1, 0)) == .one)
    }

    @Test func posterize() throws {
        var b = Block(); b.u16(4); b.u16(0)
        #expect(close(try adjust("post", Data(b.data), (0.3, 0, 1)), (1.0 / 3, 0, 1)))
    }

    func levelsBlock(_ records: [(Int, Int, Int, Int, Int)]) -> Data {
        var b = Block()
        b.u16(2)
        for r in records + Array(repeating: (0, 255, 0, 255, 100), count: 29 - records.count) {
            b.u16(r.0); b.u16(r.1); b.u16(r.2); b.u16(r.3); b.u16(r.4)
        }
        return Data(b.data)
    }

    @Test func levels() throws {
        let data = levelsBlock([(50, 200, 0, 255, 100)])
        #expect(close(try adjust("levl", data, (50 / 255, 125 / 255, 200 / 255)), (0, 127.5 / 255, 1), 0.5 / 255))
        // Gamma 2 brightens the middle.
        #expect(try adjust("levl", levelsBlock([(0, 255, 0, 255, 200)]), (0.25, 0.25, 0.25)).x > 0.45)
        // Each channel's own applies first, then the composite (as Photoshop's composites show): red's 0…128 → 0…255
        // keeps white, then the composite halves every channel.
        let both = levelsBlock([(0, 255, 0, 128, 100), (0, 128, 0, 255, 100)])
        #expect(close(try adjust("levl", both, (1, 1, 1)), (128 / 255, 128 / 255, 128 / 255), 1 / 255))
        #expect(throws: OwnDecodeError.corrupt) { try PSDAdjustments.adjustment(key: "levl", data: Data([0, 2, 0, 50])) }
    }

    func curvesBlock(channels: UInt32, _ curves: [[(Int, Int)]]) -> Data {
        var b = Block()
        b.u8(0); b.u16(1); b.u32(Int(channels))
        for points in curves {
            b.u16(points.count)
            for (input, output) in points { b.u16(output); b.u16(input) }
        }
        return Data(b.data)
    }

    @Test func curves() throws {
        let data = curvesBlock(channels: 1, [[(0, 0), (128, 200), (255, 255)]])
        let f = try #require(try PSDAdjustments.adjustment(key: "curv", data: data))
        var previous: Float = -1
        for i in 0...255 {
            var v = SIMD3<Float>(repeating: Float(i) / 255)
            f(&v)
            #expect(v.x >= previous)
            previous = v.x
        }
        #expect(close(try adjust("curv", data, (0, 128 / 255, 1)), (0, 200 / 255, 1), 0.5 / 255))
        // Bit 2 is green alone: red and blue stay.
        let green = curvesBlock(channels: 4, [[(0, 255), (255, 0)]])
        #expect(close(try adjust("curv", green, (0.2, 0.2, 0.2)), (0.2, 0.8, 0.2)))
        // A damaged end point above 255 still gives values in 0…1.
        let high = curvesBlock(channels: 4, [[(10, 300), (255, 255)]])
        #expect(close(try adjust("curv", high, (0, 0, 0)), (0, 1, 0)))
        #expect(throws: OwnDecodeError.corrupt) {
            try PSDAdjustments.adjustment(key: "curv", data: Data([0, 0, 1, 0, 0, 0, 1, 0, 9, 0, 0]))
        }
    }

    func hueSaturationBlock(colorize: Bool = false, colorizeHSL: (Int, Int, Int) = (0, 0, 0), master: (Int, Int, Int),
                            reds: (Int, Int, Int) = (0, 0, 0)) -> Data {
        var b = Block()
        b.u16(2); b.u8(colorize ? 1 : 0); b.u8(0)
        b.u16(colorizeHSL.0); b.u16(colorizeHSL.1); b.u16(colorizeHSL.2)
        b.u16(master.0); b.u16(master.1); b.u16(master.2)
        let ranges = [(315, 345, 15, 45), (15, 45, 75, 105), (75, 105, 135, 165), (135, 165, 195, 225), (195, 225, 255, 285), (255, 285, 315, 345)]
        for (i, r) in ranges.enumerated() {
            b.u16(r.0); b.u16(r.1); b.u16(r.2); b.u16(r.3)
            let s = i == 0 ? reds : (0, 0, 0)
            b.u16(s.0); b.u16(s.1); b.u16(s.2)
        }
        return Data(b.data)
    }

    /// A non-zero first byte stores each curve as 256 output bytes, one per input value; the curves extra
    /// data ('Crv ') may follow.
    @Test func curvesInAnUnknownFormIsLeftOut() throws {
        #expect(try PSDAdjustments.adjustment(key: "curv", data: Data([1, 0, 1, 0, 0, 0, 1] + [UInt8](repeating: 0, count: 256))) == nil)
    }

    func hslLightness(_ c: SIMD3<Float>) -> Float { (c.max() + c.min()) / 2 }

    @Test func hueSaturation() throws {
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (180, 0, 0)), (1, 0, 0)), (0, 1, 1)))
        // Saturation −100: the grey of the colour's HSL lightness.
        let grey = try adjust("hue2", hueSaturationBlock(master: (0, -100, 0)), (0.8, 0.4, 0.2))
        #expect(close(grey, (0.5, 0.5, 0.5)))
        // Saturation +100 saturates fully, keeping hue and lightness; +50 doubles the saturation (a / (1 − a) more).
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 100, 0)), (0.6, 0.5, 0.4)), (1, 0.5, 0)))
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 50, 0)), (0.6, 0.5, 0.4)), (0.7, 0.5, 0.3)))
        // The reds' own setting turns red green and leaves blue alone.
        let redsOnly = hueSaturationBlock(master: (0, 0, 0), reds: (120, 0, 0))
        #expect(close(try adjust("hue2", redsOnly, (1, 0, 0)), (0, 1, 0)))
        #expect(close(try adjust("hue2", redsOnly, (0, 0, 1)), (0, 0, 1)))
        // Lightness +100 is white, −100 black.
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 0, 100)), (0.3, 0.6, 0.1)), (1, 1, 1)))
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 0, -100)), (0.3, 0.6, 0.1)), (0, 0, 0)))
        // A range's lightness moves the colour above its darkest channel: −100 leaves the grey of that channel,
        // +100 the grey of the brightest; the master's lightness then applies on top.
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 0, 0), reds: (0, 0, -100)), (0.8, 0.3, 0.2)), (0.2, 0.2, 0.2)))
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 0, 0), reds: (0, 0, 100)), (0.8, 0.3, 0.2)), (0.8, 0.8, 0.8)))
        #expect(close(try adjust("hue2", hueSaturationBlock(master: (0, 0, 50), reds: (0, 0, -100)), (0.8, 0.3, 0.2)), (0.6, 0.6, 0.6)))
        // Colorize: one hue for everything, at the colour's HSL lightness; a grey turns blue.
        let blue = try adjust("hue2", hueSaturationBlock(colorize: true, colorizeHSL: (240, 50, 0), master: (0, 0, 0)), (0.5, 0.5, 0.5))
        #expect(close(blue, (0.25, 0.25, 0.75)))
        let dark = try adjust("hue2", hueSaturationBlock(colorize: true, colorizeHSL: (0, 100, -50), master: (0, 0, 0)), (0.6, 0.2, 0.4))
        #expect(close(dark, (0.4, 0, 0)))
    }

    @Test func brightnessContrastLegacyAndModern() throws {
        var legacy = Block(); legacy.u16(50); legacy.u16(0); legacy.u16(127); legacy.u8(0)
        #expect(close(try adjust("brit", Data(legacy.data), (0, 0.5, 1)), (50 / 255, 0.5 + 50 / 255, 1)))
        // Contrast spreads values away from the mean.
        var contrast = Block(); contrast.u16(0); contrast.u16(50); contrast.u16(127); contrast.u8(0)
        let spread = try adjust("brit", Data(contrast.data), (0.3, 127 / 255, 0.7))
        #expect(spread.x < 0.3 && abs(spread.y - 127 / 255) < 0.002 && spread.z > 0.7)

        let modern = descriptorBlock([("Vrsn", 1), ("Brgh", 50), ("Cntr", 0), ("means", 127)], extraCount: 1) {
            $0.id("useLegacy"); $0.os("bool"); $0.data.append(0)
        }
        let m = try adjust("CgEd", modern, (0, 0.5, 1))
        #expect(m.x == 0 && m.z == 1 && m.y > 0.55)
        let old = descriptorBlock([("Vrsn", 1), ("Brgh", 50), ("Cntr", 0), ("means", 127)], extraCount: 1) {
            $0.id("useLegacy"); $0.os("bool"); $0.data.append(1)
        }
        #expect(close(try adjust("CgEd", old, (0, 0.5, 1)), (50 / 255, 0.5 + 50 / 255, 1)))
    }

    @Test func descriptorAdjustmentsRejectNonFiniteNumbers() throws {
        // 1e300 is finite as a double but infinite as a Float.
        for bad in [Double.infinity, -Double.infinity, Double.nan, 1e300] {
            for (key, name) in [("CgEd", "Brgh"), ("CgEd", "Cntr"), ("CgEd", "means"), ("vibA", "vibrance"), ("vibA", "Strt")] {
                for legacy: UInt8 in [0, 1] {
                    let data = descriptorBlock([], extraCount: 2) {
                        $0.id(name); $0.os("doub"); $0.double(bad)
                        $0.id("useLegacy"); $0.os("bool"); $0.data.append(legacy)
                    }
                    #expect(throws: OwnDecodeError.corrupt, "\(key) \(name) \(bad)") { try PSDAdjustments.adjustment(key: key, data: data) }
                }
            }
        }
    }

    @Test func exposure() throws {
        var b = Block(); b.u16(1); b.f32(1); b.f32(0); b.f32(1)
        let v = try adjust("expA", Data(b.data), (0.2, 0.4, 0))
        #expect(abs(linear(v.x) - 2 * linear(0.2)) < 0.002)
        #expect(abs(linear(v.y) - 2 * linear(0.4)) < 0.002)
        #expect(v.z == 0)
        #expect(throws: OwnDecodeError.corrupt) { try PSDAdjustments.adjustment(key: "expA", data: Data([0, 1, 0, 0])) }
    }

    @Test func unknownKeyIsNil() throws {
        #expect(try PSDAdjustments.adjustment(key: "clrL", data: Data([1, 2, 3])) == nil)
        #expect(try PSDAdjustments.adjustment(key: "zzzz", data: Data()) == nil)
    }

    func balanceBlock(midtones: (Int, Int, Int), preserve: Bool) -> Data {
        var b = Block()
        for _ in 0..<3 { b.u16(0) }
        b.u16(midtones.0); b.u16(midtones.1); b.u16(midtones.2)
        for _ in 0..<3 { b.u16(0) }
        b.u8(preserve ? 1 : 0); b.u8(0)
        return Data(b.data)
    }

    @Test func colourBalance() throws {
        let warmer = try adjust("blnc", balanceBlock(midtones: (100, 0, 0), preserve: false), (0.5, 0.5, 0.5))
        #expect(warmer.x > 0.6 && warmer.y == 0.5 && warmer.z == 0.5)
        let kept = try adjust("blnc", balanceBlock(midtones: (100, 0, 0), preserve: true), (0.5, 0.5, 0.5))
        #expect(kept.x > kept.y && abs(lum(kept) - 0.5) < 0.002)
        // Shadows and highlights settings leave black and white as they are.
        #expect(try adjust("blnc", balanceBlock(midtones: (100, 100, 100), preserve: false), (1, 1, 1)) == .one)
    }

    func blackAndWhiteBlock(tint: (Double, Double, Double)? = nil) -> Data {
        descriptorBlock([("Rd  ", 40), ("Yllw", 60), ("Grn ", 40), ("Cyn ", 60), ("Bl  ", 20), ("Mgnt", 80)], extraCount: tint == nil ? 0 : 2) { b in
            guard let tint else { return }
            b.id("useTint"); b.os("bool"); b.data.append(1)
            b.id("tintColor"); b.os("Objc"); b.header("RGBC", count: 3)
            b.id("Rd  "); b.os("doub"); b.double(tint.0)
            b.id("Grn "); b.os("doub"); b.double(tint.1)
            b.id("Bl  "); b.os("doub"); b.double(tint.2)
        }
    }

    @Test func blackAndWhite() throws {
        let data = blackAndWhiteBlock()
        #expect(close(try adjust("blwh", data, (1, 0, 0)), (0.4, 0.4, 0.4)))
        #expect(close(try adjust("blwh", data, (1, 1, 0)), (0.6, 0.6, 0.6)))
        #expect(close(try adjust("blwh", data, (0, 0, 1)), (0.2, 0.2, 0.2)))
        #expect(close(try adjust("blwh", data, (1, 1, 1)), (1, 1, 1)))
        let sepia = try adjust("blwh", blackAndWhiteBlock(tint: (225, 211, 179)), (1, 1, 0))
        #expect(sepia.x > sepia.z && abs(lum(sepia) - 0.6) < 0.002)
    }

    @Test func blackAndWhiteRejectsNonFiniteNumbers() throws {
        for bad in [Double.infinity, -Double.infinity, Double.nan] {
            let weight = descriptorBlock([], extraCount: 1) { $0.id("Rd  "); $0.os("doub"); $0.double(bad) }
            #expect(throws: OwnDecodeError.corrupt) { try PSDAdjustments.adjustment(key: "blwh", data: weight) }
            #expect(throws: OwnDecodeError.corrupt) { try PSDAdjustments.adjustment(key: "blwh", data: blackAndWhiteBlock(tint: (bad, 0, 0))) }
        }
    }

    /// These closures run once per pixel, so they must not allocate or chase nested arrays: 12 MP took ~0.5 s
    /// (levels, curves) to ~1.8 s (selective colour) on one core in a release build, now ~0.1–0.3 s. Unoptimized
    /// timings say little about that and swing twofold with the parallel suites, so only release builds run it.
    @Test(.enabled(if: !_isDebugAssertConfiguration())) func perPixelAdjustmentsAreFast() throws {
        let count = 12_000_000
        let blocks: [(String, Data)] = [
            ("levl", levelsBlock([(10, 240, 5, 250, 120), (0, 200, 0, 255, 100)])),
            ("curv", curvesBlock(channels: 3, [[(0, 0), (128, 200), (255, 255)], [(0, 20), (255, 230)]])),
            ("selc", selectiveBlock(relative: true, reds: (30, -20, 10, 5))),
            ("blwh", blackAndWhiteBlock()),
        ]
        for (key, data) in blocks {
            let f = try #require(try PSDAdjustments.adjustment(key: key, data: data))
            var elapsed = Duration.seconds(100), sum = SIMD3<Float>.zero
            for _ in 0..<2 {
                let start = ContinuousClock.now
                for i in 0..<count {
                    var c = SIMD3<Float>(Float(i & 255), Float(i >> 8 & 255), Float(i >> 16 & 255)) / 255
                    f(&c)
                    sum += c
                }
                elapsed = min(elapsed, ContinuousClock.now - start)
            }
            #expect(sum.x.isFinite)
            #expect(elapsed < .milliseconds(400), "\(key) took \(elapsed)")
        }
    }

    @Test func channelMixer() throws {
        var swap = Block(); swap.u16(1); swap.u16(0)
        for record in [[0, 100, 0, 0, 0], [0, 100, 0, 0, 0], [0, 0, 100, 0, 20], [0, 0, 0, 100, 0]] { for v in record { swap.u16(v) } }
        #expect(close(try adjust("mixr", Data(swap.data), (0.2, 0.6, 0.5)), (0.6, 0.6, 0.7)))
        var mono = Block(); mono.u16(1); mono.u16(1)
        for record in [[40, 40, 20, 0, 0], [0, 100, 0, 0, 0], [0, 0, 100, 0, 0], [0, 0, 0, 100, 0]] { for v in record { mono.u16(v) } }
        #expect(close(try adjust("mixr", Data(mono.data), (1, 0.5, 0)), (0.6, 0.6, 0.6)))
    }

    @Test func vibrance() throws {
        let saturation = descriptorBlock([("vibrance", 0), ("Strt", -100)])
        let grey = try adjust("vibA", saturation, (0.8, 0.4, 0.2))
        #expect(abs(grey.x - grey.z) < 0.001 && abs(lum(grey) - lum(SIMD3(0.8, 0.4, 0.2))) < 0.002)
        // Vibrance raises a muted colour's saturation more than a vivid one's, and a grey stays grey.
        let vibrance = descriptorBlock([("vibrance", 50), ("Strt", 0)])
        let muted = try adjust("vibA", vibrance, (0.55, 0.5, 0.45))
        let vivid = try adjust("vibA", vibrance, (0.9, 0.5, 0.1))
        #expect((muted.x - muted.z) / 0.1 > (vivid.x - vivid.z) / 0.8)
        #expect(close(try adjust("vibA", vibrance, (0.5, 0.5, 0.5)), (0.5, 0.5, 0.5)))
        // Both at -100 stop at grey instead of flipping to the complement; both at +100 stop at full saturation.
        let least = try adjust("vibA", descriptorBlock([("vibrance", -100), ("Strt", -100)]), (0.6, 0.4, 0.4))
        #expect(close(least, (0.46, 0.46, 0.46)))
        let most = try adjust("vibA", descriptorBlock([("vibrance", 100), ("Strt", 100)]), (0.55, 0.5, 0.5))
        #expect(close(most, (0.585, 0.485, 0.485)))
    }

    func photoFilterBlock(space: Int, _ colour: [Int], density: Int, preserve: Bool) -> Data {
        var b = Block()
        b.u16(2); b.u16(space)
        for v in colour + Array(repeating: 0, count: 4 - colour.count) { b.u16(v) }
        b.u32(density); b.u8(preserve ? 1 : 0); b.u8(0); b.u8(0); b.u8(0)
        return Data(b.data)
    }

    @Test func photoFilter() throws {
        let red = photoFilterBlock(space: 0, [65535, 0, 0], density: 100, preserve: false)
        #expect(close(try adjust("phfl", red, (1, 1, 1)), (1, 0, 0)))
        let half = photoFilterBlock(space: 0, [65535, 0, 0], density: 50, preserve: false)
        #expect(close(try adjust("phfl", half, (1, 1, 1)), (1, 0.5, 0.5)))
        // A warming filter in Lab (L 67, a 32, b 73) with preserve luminosity.
        let warm = photoFilterBlock(space: 7, [6700, 3200, 7300], density: 25, preserve: true)
        let v = try adjust("phfl", warm, (0.5, 0.5, 0.5))
        #expect(v.x > v.z && abs(lum(v) - 0.5) < 0.002)
        // HSB (pure green: 120°, full saturation and brightness) and CMYK (cyan; 65535 is no ink).
        let hsb = photoFilterBlock(space: 1, [21845, 65535, 65535], density: 100, preserve: false)
        #expect(close(try adjust("phfl", hsb, (1, 1, 1)), (0, 1, 0)))
        let cmyk = photoFilterBlock(space: 2, [0, 65535, 65535, 65535], density: 100, preserve: false)
        #expect(close(try adjust("phfl", cmyk, (1, 1, 1)), (0, 1, 1)))
    }

    func selectiveBlock(relative: Bool, reds: (Int, Int, Int, Int)) -> Data {
        var b = Block()
        b.u16(1); b.u16(relative ? 0 : 1)
        for i in 0..<10 {
            let r = i == 1 ? reds : (0, 0, 0, 0)
            b.u16(r.0); b.u16(r.1); b.u16(r.2); b.u16(r.3)
        }
        return Data(b.data)
    }

    @Test func selectiveColour() throws {
        let absolute = selectiveBlock(relative: false, reds: (100, 0, 0, 0))
        #expect(close(try adjust("selc", absolute, (1, 0, 0)), (0, 0, 0)))
        #expect(close(try adjust("selc", absolute, (0.5, 0.5, 0.5)), (0.5, 0.5, 0.5)))
        // Relative adds cyan in proportion to the cyan already there: none in pure red.
        #expect(close(try adjust("selc", selectiveBlock(relative: true, reds: (100, 0, 0, 0)), (1, 0, 0)), (1, 0, 0)))
        #expect(close(try adjust("selc", selectiveBlock(relative: false, reds: (0, 0, 0, 100)), (1, 0, 0)), (0, 0, 0)))
    }

    func gradientMapBlock(reverse: Bool, space: Int = 0, interpolation: String? = nil, stops: [(location: Int, rgb: (Int, Int, Int))]) -> Data {
        var b = Block()
        b.u16(interpolation == nil ? 1 : 3); b.u8(reverse ? 1 : 0); b.u8(0)
        if let interpolation { for u in interpolation.utf8 { b.u8(u) } }
        let name = Array("Map".utf16) + [0]
        b.u32(name.count); for u in name { b.u16(Int(u)) }
        b.u16(stops.count)
        for stop in stops {
            b.u32(stop.location); b.u32(50); b.u16(space)
            b.u16(stop.rgb.0); b.u16(stop.rgb.1); b.u16(stop.rgb.2); b.u16(space == 2 ? 65535 : 0); b.u16(0)
        }
        b.u16(2)
        for location in [0, 4096] { b.u32(location); b.u32(50); b.u16(255) }
        return Data(b.data)
    }

    @Test func gradientMap() throws {
        let data = gradientMapBlock(reverse: false, stops: [(0, (65535, 0, 0)), (4096, (0, 0, 65535))])
        #expect(close(try adjust("grdm", data, (0, 0, 0)), (1, 0, 0)))
        #expect(close(try adjust("grdm", data, (1, 1, 1)), (0, 0, 1)))
        #expect(close(try adjust("grdm", data, (0.5, 0.5, 0.5)), (0.5, 0, 0.5)))
        let reversed = gradientMapBlock(reverse: true, stops: [(0, (65535, 0, 0)), (4096, (0, 0, 65535))])
        #expect(close(try adjust("grdm", reversed, (0, 0, 0)), (0, 0, 1)))
        let hsb = gradientMapBlock(reverse: false, space: 1, stops: [(0, (0, 65535, 65535)), (4096, (43690, 65535, 32768))])
        #expect(close(try adjust("grdm", hsb, (0, 0, 0)), (1, 0, 0)))
        #expect(close(try adjust("grdm", hsb, (1, 1, 1)), (0, 0, 0.5)))
        let cmyk = gradientMapBlock(reverse: false, space: 2, stops: [(0, (65535, 0, 65535)), (4096, (65535, 65535, 65535))])
        #expect(close(try adjust("grdm", cmyk, (0, 0, 0)), (1, 0, 1)))
        #expect(close(try adjust("grdm", cmyk, (1, 1, 1)), (1, 1, 1)))
        #expect(throws: OwnDecodeError.corrupt) {
            try PSDAdjustments.adjustment(key: "grdm", data: Data([0, 1, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]))
        }
    }

    /// Version 3 (current Photoshop) puts the interpolation method's key between the dither byte and the name.
    @Test func gradientMapVersion3() throws {
        for method in ["Gcls", "Perc", "Lnr ", "Smth"] {
            let data = gradientMapBlock(reverse: false, interpolation: method, stops: [(0, (65535, 0, 0)), (4096, (0, 0, 65535))])
            #expect(close(try adjust("grdm", data, (0, 0, 0)), (1, 0, 0)))
            #expect(close(try adjust("grdm", data, (1, 1, 1)), (0, 0, 1)))
            #expect(close(try adjust("grdm", data, (0.5, 0.5, 0.5)), (0.5, 0, 0.5)))
        }
    }
}
