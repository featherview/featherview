import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct HistogramTests {
    private func peak(_ bins: [Float]) -> Int { bins.indices.max { bins[$0] < bins[$1] }! }

    /// Extended linear sRGB floats, R, G, B, A per pixel, straight alpha.
    private func hdrImage(_ width: Int, _ height: Int, _ floats: [Float]) throws -> CGImage {
        let data = floats.withUnsafeBytes { Data($0) }
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: width * 16,
            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.floatComponents.rawValue
                                     | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @Test func transparentPixelsNotCounted() throws {
        var image = Fixtures.solid(100, 100, (255, 255, 255, 255))
        for y in 0..<50 { for x in 0..<100 { image[x, y] = (0, 0, 0, 0) } }
        let histogram = Histogram.compute(try #require(image.makeCGImage()), headroom: nil)
        #expect(histogram.shadowsClipped == 0)
        #expect(histogram.highlightsClipped == 1)
        #expect(histogram.luminance[0] == 0)
        #expect(histogram.red[0] == 0)
        #expect(histogram.luminance[255] == 1)
    }

    @Test func hdrClipsOnlyAtBlackAndHeadroom() throws {
        // 20 pixels: 10 at linear 0.01 (dark, not black), 5 at 2.0, 2 at 0, 2 at the headroom 4, 1 transparent.
        let pixels: [[Float]] = Array(repeating: [0.01, 0.01, 0.01, 1], count: 10) + Array(repeating: [2, 2, 2, 1], count: 5)
            + Array(repeating: [0, 0, 0, 1], count: 2) + Array(repeating: [4, 4, 4, 1], count: 2) + [[0, 0, 0, 0]]
        let histogram = Histogram.compute(try hdrImage(20, 1, pixels.flatMap { $0 }), headroom: 4)
        #expect(abs(histogram.shadowsClipped - 2.0 / 19) < 1e-9)
        #expect(abs(histogram.highlightsClipped - 2.0 / 19) < 1e-9)
    }

    @Test(arguments: [2.8, 4.0])
    func hdrWhiteAtHeadroomClips(headroom: Double) throws {
        // White at exactly the headroom; at 2.8 the Float-weighted luminance sum rounds one ulp low.
        let v = Float(headroom)
        let histogram = Histogram.compute(try hdrImage(2, 1, [v, v, v, 1, v, v, v, 1]), headroom: headroom)
        #expect(histogram.highlightsClipped == 1)
        #expect(peak(histogram.luminance) == 255)
        #expect(peak(histogram.red) == 255)
    }

    @Test func largeHdrSampledKeepsFractions() throws {
        // 2000 × 2000, top half black, bottom half at linear 2.0.
        let half = 2000 * 1000
        let floats = [Float](unsafeUninitializedCapacity: 2 * half * 4) { buffer, count in
            for i in 0..<(2 * half) {
                let v: Float = i < half ? 0 : 2
                buffer[i * 4] = v; buffer[i * 4 + 1] = v; buffer[i * 4 + 2] = v; buffer[i * 4 + 3] = 1
            }
            count = 2 * half * 4
        }
        let histogram = Histogram.compute(try hdrImage(2000, 2000, floats), headroom: 4)
        #expect(abs(histogram.shadowsClipped - 0.5) < 0.01)
        #expect(histogram.highlightsClipped == 0)
        #expect(peak(histogram.luminance) == 0 || peak(histogram.luminance) == 127)
    }

    @Test func largeSdrSampledKeepsFractions() throws {
        // 2400 × 2400, top half black, bottom half white, and a 1 px white column that sampling steps over.
        let width = 2400, half = width * width / 2
        var pixels = [UInt8](repeating: 255, count: width * width * 4)
        for i in 0..<half { pixels[i * 4] = 0; pixels[i * 4 + 1] = 0; pixels[i * 4 + 2] = 0 }
        for y in 0..<(width / 2) { let i = (y * width + 1) * 4; pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255 }
        let image = try #require(RGBAImage(width: width, height: width, pixels: pixels).makeCGImage())
        let histogram = Histogram.compute(image, headroom: nil)
        #expect(abs(histogram.shadowsClipped - 0.5) < 0.01)
        #expect(abs(histogram.highlightsClipped - 0.5) < 0.01)
        // Full size would count the column's 1200 pixels: (half + 1200) / total.
        #expect(histogram.highlightsClipped != Double(half + width / 2) / Double(width * width))
    }

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
