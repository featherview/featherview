import Foundation
import Testing
@testable import FeatherviewCore

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

    @Test func clampsCount() {
        let image = gradient()
        #expect(ColourQuantizer.reduce(image, colours: 1, dither: false) == ColourQuantizer.reduce(image, colours: 2, dither: false))
        #expect(ColourQuantizer.reduce(image, colours: 1000, dither: false)
            == ColourQuantizer.reduce(image, colours: 256, dither: false))
    }
}
