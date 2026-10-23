import CoreImage
import Foundation
import Testing
@testable import FeatherviewCore

private func near(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ e: (Int, Int, Int, Int), _ tolerance: Int = 1) -> Bool {
    abs(Int(p.r) - e.0) <= tolerance && abs(Int(p.g) - e.1) <= tolerance
        && abs(Int(p.b) - e.2) <= tolerance && abs(Int(p.a) - e.3) <= tolerance
}

private func grey(_ v: Int, width: Int = 8, height: Int = 8) -> CIImage {
    let c = Double(v) / 255
    return PipelineFixtures.solid(RGBAColor(red: c, green: c, blue: c), width: width, height: height)
}

/// Auto adjust runs Vision, which needs a free cooperative-pool thread: off the pool, as the batch runs it.
private func autoAdjusted(_ image: @escaping @Sendable () -> CIImage) async throws -> RGBAImage {
    try await offPool { try PipelineFixtures.pixels(ColourStep.apply(image(), colour { $0.autoAdjust = true }, scale: 1)) }
}

private func colour(_ configure: (inout ColourSettings) -> Void) -> ColourSettings {
    var s = ColourSettings()
    s.isOn = true
    configure(&s)
    return s
}

private func filter(_ configure: (inout FilterSettings) -> Void) -> FilterSettings {
    var s = FilterSettings()
    s.isOn = true
    configure(&s)
    return s
}

@Suite struct ColourStepsTests {
    @Test func offIsIdentity() throws {
        let image = PipelineFixtures.quadrants(width: 8, height: 8)
        var off = colour { $0.negative = true; $0.brightness = 100; $0.blur = 50 }
        off.isOn = false
        #expect(try PipelineFixtures.pixels(ColourStep.apply(image, off, scale: 1)) == PipelineFixtures.pixels(image))
        #expect(try PipelineFixtures.pixels(ColourStep.apply(image, colour { _ in }, scale: 1))
            == PipelineFixtures.pixels(image))
    }

    /// A 1x1 image (spacer GIF, tracking pixel) is auto-adjusted like a larger one of the same colour, not turned black.
    @Test func autoAdjustOnOnePixelMatchesALargerImage() async throws {
        let big = try await autoAdjusted { grey(128, width: 2, height: 2) }[0, 0]
        var pixel = RGBAImage(width: 1, height: 1)
        pixel[0, 0] = (128, 128, 128, 255)
        let one = pixel
        let images: [@Sendable () -> CIImage] = [{ grey(128, width: 1, height: 1) }, { grey(128, width: 1, height: 100) },
                                                 { PipelineFixtures.fromRGBA(one) }]
        for image in images {
            let out = try await autoAdjusted(image)[0, 0]
            #expect(near(out, (Int(big.r), Int(big.g), Int(big.b), 255)), "\(out) vs \(big)")
        }
    }

    /// A logo or cut-out gets the same correction as the same colours without transparency.
    @Test func autoAdjustMeasuresColoursNotAlpha() async throws {
        @Sendable func gradient(alpha: UInt8, height: Int = 16) -> CIImage {
            var image = RGBAImage(width: 64, height: height, pixels: [UInt8](repeating: 0, count: 64 * height * 4))
            for y in 0..<16 { for x in 0..<64 { image[x, y] = (UInt8(40 + x), UInt8(200 - x), UInt8(90 + x / 2), alpha) } }
            return PipelineFixtures.fromRGBA(image)
        }
        let opaque = try await autoAdjusted { gradient(alpha: 255) }[10, 8]
        let half = try await autoAdjusted { gradient(alpha: 128) }[10, 8]
        let padded = try await autoAdjusted { gradient(alpha: 255, height: 64) }[10, 8]
        #expect(near(half, (Int(opaque.r), Int(opaque.g), Int(opaque.b), 128), 3), "\(half) vs \(opaque)")
        #expect(near(padded, (Int(opaque.r), Int(opaque.g), Int(opaque.b), 255), 3), "\(padded) vs \(opaque)")
    }

    @Test func greyscaleUsesRec709() throws {
        let green = PipelineFixtures.solid(RGBAColor(red: 0, green: 1, blue: 0), width: 4, height: 4)
        let out = try PipelineFixtures.pixels(ColourStep.apply(green, colour { $0.greyscale = true }, scale: 1))
        let v = Int((0.7152 * 255).rounded())
        #expect(near(out[2, 2], (v, v, v, 255)))
    }

    @Test func negativeKeepsAlpha() throws {
        let red = PipelineFixtures.solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 4, height: 4)
        let out = try PipelineFixtures.pixels(ColourStep.apply(red, colour { $0.negative = true }, scale: 1))
        #expect(near(out[1, 1], (0, 255, 255, 128)))
    }

    @Test func brightnessAddsToEncodedValues() throws {
        let out = try PipelineFixtures.pixels(ColourStep.apply(grey(128), colour { $0.brightness = 51 }, scale: 1))
        #expect(near(out[3, 3], (179, 179, 179, 255)))
    }

    @Test func contrastMinusMaxIsFlatGrey() throws {
        let image = PipelineFixtures.quadrants(width: 8, height: 8)
        let out = try PipelineFixtures.pixels(ColourStep.apply(image, colour { $0.contrast = -127 }, scale: 1))
        for (x, y) in [(0, 0), (7, 0), (0, 7), (7, 7)] { #expect(near(out[x, y], (128, 128, 128, 255))) }
    }

    @Test func gammaTwoBrightens() throws {
        let out = try PipelineFixtures.pixels(ColourStep.apply(grey(64), colour { $0.gamma = 2 }, scale: 1))
        #expect(near(out[3, 3], (128, 128, 128, 255)))
    }

    @Test func saturationMinusMaxIsGrey() throws {
        let image = PipelineFixtures.solid(RGBAColor(red: 200.0 / 255, green: 50.0 / 255, blue: 100.0 / 255),
                                           width: 4, height: 4)
        let p = try PipelineFixtures.pixels(ColourStep.apply(image, colour { $0.saturation = -255 }, scale: 1))[1, 1]
        #expect(abs(Int(p.r) - Int(p.g)) <= 1 && abs(Int(p.g) - Int(p.b)) <= 1)
    }

    @Test func balanceMovesOneChannel() throws {
        let out = try PipelineFixtures.pixels(ColourStep.apply(grey(128), colour { $0.balanceRed = 51 }, scale: 1))
        #expect(near(out[3, 3], (179, 128, 128, 255)))
    }

    @Test func blurKeepsEdgesBright() throws {
        let out = try PipelineFixtures.pixels(ColourStep.apply(grey(255, width: 20, height: 20),
                                                               colour { $0.blur = 60 }, scale: 1))
        #expect(out.width == 20 && out.height == 20)
        for (x, y) in [(0, 0), (19, 0), (0, 19), (19, 19)] { #expect(near(out[x, y], (255, 255, 255, 255))) }
    }

    @Test func blurScalesWithPreview() throws {
        let image = PipelineFixtures.quadrants(width: 32, height: 32)
        let preview = try PipelineFixtures.pixels(ColourStep.apply(image, colour { $0.blur = 40 }, scale: 0.5))
        let half = try PipelineFixtures.pixels(ColourStep.apply(image, colour { $0.blur = 20 }, scale: 1))
        let full = try PipelineFixtures.pixels(ColourStep.apply(image, colour { $0.blur = 40 }, scale: 1))
        #expect(preview == half)
        #expect(preview != full)
    }

    @Test func orderIsSpecOrder() throws {
        // Negative comes before brightness: 51 → 204 → 255 (the other way round: 51 → 102 → 153).
        let out = try PipelineFixtures.pixels(ColourStep.apply(grey(51),
                                                               colour { $0.negative = true; $0.brightness = 51 }, scale: 1))
        #expect(near(out[3, 3], (255, 255, 255, 255)))
    }
}

@Suite struct FilterStepsTests {
    @Test func autoLevelsStretchesAGreyRamp() throws {
        var ramp = RGBAImage(width: 128, height: 4)
        for y in 0..<4 { for x in 0..<128 { let v = UInt8(64 + x); ramp[x, y] = (v, v, v, 255) } }
        let out = try PipelineFixtures.pixels(FilterStep.apply(PipelineFixtures.fromRGBA(ramp),
                                                               filter { $0.autoLevels = true }, scale: 1))
        #expect(near(out[0, 1], (0, 0, 0, 255), 2))
        #expect(near(out[127, 1], (255, 255, 255, 255), 2))
    }

    @Test func autoLevelsMeasuresHalfTransparentPixelsByTheirColour() throws {
        var ramp = RGBAImage(width: 128, height: 4)
        for y in 0..<4 { for x in 0..<128 { let v = UInt8(64 + x); ramp[x, y] = (v, v, v, 128) } }
        let out = try PipelineFixtures.pixels(FilterStep.apply(PipelineFixtures.fromRGBA(ramp),
                                                               filter { $0.autoLevels = true }, scale: 1))
        #expect(near(out[0, 1], (0, 0, 0, 128), 3))
        #expect(near(out[127, 1], (255, 255, 255, 128), 3))
    }

    @Test func autoLevelsIgnoresTransparentPixels() throws {
        var ramp = RGBAImage(width: 256, height: 4, pixels: [UInt8](repeating: 0, count: 256 * 4 * 4))
        for y in 0..<4 { for x in 0..<128 { let v = UInt8(64 + x); ramp[x, y] = (v, v, v, 255) } }
        let out = try PipelineFixtures.pixels(FilterStep.apply(PipelineFixtures.fromRGBA(ramp),
                                                               filter { $0.autoLevels = true }, scale: 1))
        #expect(near(out[0, 1], (0, 0, 0, 255), 2))
        #expect(near(out[127, 1], (255, 255, 255, 255), 2))
        #expect(out[200, 1].a == 0)
    }

    @Test func autoLevelsLeavesAFlatImage() throws {
        let out = try PipelineFixtures.pixels(FilterStep.apply(grey(100), filter { $0.autoLevels = true }, scale: 1))
        #expect(near(out[3, 3], (100, 100, 100, 255)))
    }

    @Test func warmerIsRedder() throws {
        let p = try PipelineFixtures.pixels(FilterStep.apply(grey(128), filter { $0.colourTemperature = 50 }, scale: 1))[3, 3]
        #expect(p.r > p.b)
    }

    @Test func coolerIsBluer() throws {
        let p = try PipelineFixtures.pixels(FilterStep.apply(grey(128), filter { $0.colourTemperature = -50 }, scale: 1))[3, 3]
        #expect(p.b > p.r)
    }

    @Test func sepiaFullTurnsGreyBrownish() throws {
        let p = try PipelineFixtures.pixels(FilterStep.apply(grey(128), filter { $0.sepia = 100 }, scale: 1))[3, 3]
        #expect(p.r > p.g && p.g > p.b)
    }

    @Test func unsharpMaskKeepsAFlatImage() throws {
        let out = try PipelineFixtures.pixels(FilterStep.apply(grey(128, width: 16, height: 16),
                                                               filter { $0.unsharpMask = 100 }, scale: 1))
        for (x, y) in [(0, 0), (15, 0), (8, 8), (15, 15)] { #expect(near(out[x, y], (128, 128, 128, 255))) }
    }

    /// Presets are read from disk: out-of-range values act like the nearest valid one.
    @Test func outOfRangeValuesAreClamped() throws {
        let grey = PipelineFixtures.solid(RGBAColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), width: 4, height: 4)
        var wild = ColourSettings(), edge = ColourSettings()
        wild.isOn = true; edge.isOn = true
        wild.contrast = 10_000; edge.contrast = 127
        wild.blur = 100_000; edge.blur = 99
        wild.gamma = 1_000; edge.gamma = 6.99
        #expect(try PipelineFixtures.pixels(ColourStep.apply(grey, wild, scale: 1))
                == PipelineFixtures.pixels(ColourStep.apply(grey, edge, scale: 1)))
    }
}
