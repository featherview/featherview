import Foundation
import Testing
@testable import FeatherviewCore

#if DEBUG
private let isOptimised = false
#else
private let isOptimised = true
#endif

@Suite struct ColourQuantizerTests {
    private func gradient(_ size: Int = 64) -> RGBAImage {
        var image = RGBAImage(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                image[x, y] = (UInt8(x * 255 / (size - 1)), UInt8(y * 255 / (size - 1)),
                               UInt8((x + y) * 255 / (2 * size - 2)), 255)
            }
        }
        return image
    }

    private func distinct(_ image: RGBAImage) -> Set<UInt32> {
        Set((0..<image.width * image.height).map { i in
            UInt32(image.pixels[i * 4]) << 16 | UInt32(image.pixels[i * 4 + 1]) << 8 | UInt32(image.pixels[i * 4 + 2])
        })
    }

    @Test(arguments: [false, true]) func atMostNColours(dither: Bool) {
        #expect(distinct(ColourQuantizer.reduce(gradient(), colours: 16, dither: dither)).count <= 16)
    }

    @Test(arguments: [false, true]) func twoColoursIsBlackAndWhite(dither: Bool) {
        let out = ColourQuantizer.reduce(gradient(), colours: 2, dither: dither)
        #expect(distinct(out) == [0, 0xFFFFFF])
        if !dither {
            #expect(out[0, 0].r == 0)
            #expect(out[63, 63].r == 255)
        }
    }

    @Test func alphaUntouched() {
        var image = gradient()
        for i in stride(from: 3, to: image.pixels.count, by: 4) { image.pixels[i] = UInt8(i / 4 % 256) }
        let out = ColourQuantizer.reduce(image, colours: 8, dither: true)
        #expect(stride(from: 3, to: image.pixels.count, by: 4).allSatisfy { out.pixels[$0] == image.pixels[$0] })
    }

    @Test func fewerColoursThanAskedIsUnchanged() {
        var image = RGBAImage(width: 4, height: 4)
        for y in 0..<4 {
            for x in 0..<4 { image[x, y] = x < 2 ? (200, 10, 30, 255) : (y < 2 ? (5, 90, 250, 255) : (17, 17, 17, 255)) }
        }
        #expect(ColourQuantizer.reduce(image, colours: 16, dither: true) == image)
    }

    /// Fine ramps whose colours share 5-bit buckets still get (about) the colours asked for.
    @Test(arguments: [64, 128, 200]) func greyRampKeepsTheAskedColours(colours: Int) {
        var ramp = RGBAImage(width: 256, height: 4)
        for y in 0..<4 { for x in 0..<256 { ramp[x, y] = (UInt8(x), UInt8(x), UInt8(x), 255) } }
        for dither in [false, true] {
            let count = distinct(ColourQuantizer.reduce(ramp, colours: colours, dither: dither)).count
            #expect(count <= colours && count >= colours * 9 / 10)
        }
    }

    @Test func darkColoursInOneBucketStayApart() {
        var image = RGBAImage(width: 300, height: 2)
        for x in 0..<300 {
            let c = (UInt8(x % 8), UInt8(x / 8 % 8), UInt8(x / 64))
            for y in 0..<2 { image[x, y] = (c.0, c.1, c.2, 255) }
        }
        let count = distinct(ColourQuantizer.reduce(image, colours: 256, dither: false)).count
        #expect(count <= 256 && count >= 230)
    }

    /// The plan's budget: a 24 MP image well under a second (only meaningful in a release build).
    @Test(.enabled(if: isOptimised), arguments: [(256, true), (16, false)])
    func twentyFourMegapixelsUnderASecond(colours: Int, dither: Bool) {
        var noise = RGBAImage(width: 6000, height: 4000), smooth = noise
        var seed: UInt32 = 1
        for i in stride(from: 0, to: noise.pixels.count, by: 4) {
            for c in 0..<3 { seed = seed &* 1_664_525 &+ 1_013_904_223; noise.pixels[i + c] = UInt8(seed >> 24) }
            let x = i / 4 % 6000, y = i / 4 / 6000 // 60,000 colours in a smooth ramp
            smooth.pixels[i] = UInt8(x * 199 / 5999); smooth.pixels[i + 1] = UInt8(y * 199 / 3999)
            smooth.pixels[i + 2] = UInt8((x + y) % 3 * 60)
        }
        for image in [noise, smooth] {
            let start = ContinuousClock.now
            _ = ColourQuantizer.reduce(image, colours: colours, dither: dither)
            #expect(ContinuousClock.now - start < .seconds(1))
        }
    }

    /// Invisible pixels aren't in the palette: their (any) colour must not push error into visible neighbours.
    @Test func transparentPixelsPassNoErrorOn() {
        var image = RGBAImage(width: 48, height: 8)
        for y in 0..<8 {
            for x in 0..<48 {
                switch x {
                case ..<16: image[x, y] = (0, 0, 0, 0)
                case ..<24: image[x, y] = (220, 30, 30, 255)
                default: let v = UInt8(128 + (x - 24) * 5); image[x, y] = (v, v, v, 255)
                }
            }
        }
        let out = ColourQuantizer.reduce(image, colours: 4, dither: true)
        for y in 0..<8 { #expect(out[16, y] == (220, 30, 30, 255)) }
    }

    @Test func blackAndWhiteIgnoresTransparentPixels() {
        var image = RGBAImage(width: 2, height: 1)
        image[0, 0] = (100, 100, 100, 0)
        image[1, 0] = (100, 100, 100, 255)
        #expect(ColourQuantizer.reduce(image, colours: 2, dither: true)[1, 0] == (0, 0, 0, 255))
    }

    @Test func clampsCount() {
        let image = gradient()
        #expect(ColourQuantizer.reduce(image, colours: 1, dither: false) == ColourQuantizer.reduce(image, colours: 2, dither: false))
        #expect(ColourQuantizer.reduce(image, colours: 1000, dither: false)
            == ColourQuantizer.reduce(image, colours: 256, dither: false))
    }
}
