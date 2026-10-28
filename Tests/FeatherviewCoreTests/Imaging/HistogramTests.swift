import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct HistogramTests {
    private func peak(_ bins: [Float]) -> Int { bins.indices.max { bins[$0] < bins[$1] }! }

    @Test func solidMidGreyFillsOneBin() throws {
        let image = try #require(Fixtures.solid(64, 64, (128, 128, 128, 255)).makeCGImage())
        let histogram = Histogram.compute(image, headroom: nil)
        #expect(histogram.luminance.count == 256)
        #expect(histogram.luminance[128] == 1)
        #expect(histogram.luminance.enumerated().allSatisfy { $0.offset == 128 || $0.element == 0 })
        #expect(histogram.headroom == nil)
    }

    @Test func blackAndWhiteClip() throws {
        var pixels = Fixtures.solid(10, 10, (0, 0, 0, 255)).pixels
        for i in stride(from: 0, to: pixels.count / 2, by: 4) { pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255 }
        let image = try #require(RGBAImage(width: 10, height: 10, pixels: pixels).makeCGImage())
        let histogram = Histogram.compute(image, headroom: nil)
        #expect(histogram.shadowsClipped == 0.5)
        #expect(histogram.highlightsClipped == 0.5)
    }

    @Test func belowThresholdNotClipped() throws {
        var image = Fixtures.solid(50, 40, (128, 128, 128, 255))
        image[0, 0] = (255, 255, 255, 255)
        let histogram = Histogram.compute(try #require(image.makeCGImage()), headroom: nil)
        #expect(histogram.highlightsClipped > 0)
        #expect(histogram.highlightsClipped < histogram.clipThreshold)
        #expect(histogram.shadowsClipped == 0)
    }

    @Test func rgbChannelsSeparate() throws {
        let image = try #require(Fixtures.solid(16, 16, (255, 0, 0, 255)).makeCGImage())
        let histogram = Histogram.compute(image, headroom: nil)
        #expect(peak(histogram.red) == 255)
        #expect(peak(histogram.green) == 0)
        #expect(peak(histogram.blue) == 0)
    }

    @Test func hdrSpansHeadroom() throws {
        // One extended linear sRGB pixel at 2.0 in every channel.
        let floats: [Float] = [2, 2, 2, 1]
        let data = floats.withUnsafeBytes { Data($0) }
        let image = try #require(CGImage(
            width: 1, height: 1, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: 16,
            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.floatComponents.rawValue
                                     | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let histogram = Histogram.compute(image, headroom: 4)
        #expect(histogram.headroom == 4)
        #expect(peak(histogram.luminance) == 127)
        #expect(peak(histogram.red) == 127)
    }

    @Test func clippedText() {
        // The number is formatted for the current locale, as the panel shows it.
        let number = 2.4.formatted(.number.precision(.fractionLength(1)))
        #expect(HistogramText.clipped(0.024, highlights: true) == "Highlights: \(number) % clipped")
        #expect(HistogramText.clipped(0, highlights: false)
                    == "Shadows: \(0.0.formatted(.number.precision(.fractionLength(1)))) % clipped")
    }
}
