import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct NetpbmEncoderTests {
    static let image = RGBAImage(width: 2, height: 1, pixels: [255, 0, 0, 255, 10, 20, 30, 0])

    @Test func pgmIsRoundedLumaAfterTheHeader() {
        #expect(NetpbmEncoder.pgm(Self.image) == Data("P5\n2 1\n255\n".utf8) + [76, 18])
    }

    @Test func ppmIsRGBAfterTheHeaderWithoutAlpha() {
        #expect(NetpbmEncoder.ppm(Self.image) == Data("P6\n2 1\n255\n".utf8) + [255, 0, 0, 10, 20, 30])
    }

    // Plain PBM: 1 is black, one line per row.
    @Test func pbmIsOneBitBlackBelowHalfLuma() {
        var pixels: [UInt8] = []
        for gray in [0, 255, 127, 128, 0, 255] as [UInt8] { pixels += [gray, gray, gray, 255] }
        let image = RGBAImage(width: 3, height: 2, pixels: pixels)
        #expect(NetpbmEncoder.pbm(image) == Data("P1\n3 2\n101\n010\n".utf8))
    }

    // Netpbm readers may reject lines over 70 characters.
    @Test func pbmBreaksLongRows() {
        let text = String(decoding: NetpbmEncoder.pbm(RGBAImage(width: 150, height: 1)), as: UTF8.self)
        #expect(text == "P1\n150 1\n" + String(repeating: "1", count: 70) + "\n" + String(repeating: "1", count: 70) + "\n"
            + String(repeating: "1", count: 10) + "\n")
    }

    @Test func pbmIsOurEncoderAndReadsBack() throws {
        let format = try #require(FormatRegistry.format(id: "pbm"))
        #expect(format.writer == .pbm)
        let image = RGBAImage(width: 3, height: 2, pixels: [UInt8](repeating: 255, count: 24))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pbm-\(UUID().uuidString).pbm")
        defer { try? FileManager.default.removeItem(at: url) }
        try NetpbmEncoder.pbm(image).write(to: url)
        let decoded = try ImageDecoder.decode(url, maxPixelSize: nil)
        #expect(decoded.width == 3 && decoded.height == 2)
    }
}
