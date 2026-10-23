import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FITSDecoderTests {
    /// Header cards padded to 80 characters and the header to 2880 bytes, then the data, padded too.
    static func file(_ cards: [String], data: [UInt8]) -> [UInt8] {
        var header = (cards + ["END"]).flatMap { Array($0.padding(toLength: 80, withPad: " ", startingAt: 0).utf8) }
        header += [UInt8](repeating: 0x20, count: (2880 - header.count % 2880) % 2880)
        return header + data + [UInt8](repeating: 0, count: (2880 - data.count % 2880) % 2880)
    }

    static func card(_ key: String, _ value: String) -> String {
        key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + String(repeating: " ", count: max(0, 20 - value.count)) + value
    }


    @Test func eightBitShowsAsStoredBottomRowFirst() throws {
        let bytes = Self.file([Self.card("SIMPLE", "T"), Self.card("BITPIX", "8"), Self.card("NAXIS", "2"),
                               Self.card("NAXIS1", "2"), Self.card("NAXIS2", "2")], data: [10, 20, 200, 250])
        #expect(try FITSDecoder.size(Data(bytes)) == (2, 2))
        let image = try FITSDecoder.decode(Data(bytes))
        #expect(image[0, 1] == (10, 10, 10, 255) && image[1, 1].r == 20)  // first stored row is the bottom one
        #expect(image[0, 0].r == 200 && image[1, 0].r == 250)
    }

    @Test func sixteenBitIsScaledAndStretched() throws {
        // Unsigned 16-bit by the BZERO convention: stored -32768...32767 means 0...65535.
        let raw = [0, 1000, 2000, 3000].map { $0 - 32768 }
        let bytes = Self.file([Self.card("SIMPLE", "T"), Self.card("BITPIX", "16"), Self.card("NAXIS", "2"),
                               Self.card("NAXIS1", "4"), Self.card("NAXIS2", "1"), Self.card("BZERO", "32768"),
                               Self.card("BSCALE", "1.0")], data: raw.flatMap { Fixtures.be16($0 & 0xFFFF) })
        let image = try FITSDecoder.decode(Data(bytes))
        #expect(image[0, 0].r == 0 && image[1, 0].r == 85 && image[2, 0].r == 170 && image[3, 0].r == 255)
    }

    @Test func floatSkipsNaNAndThreePlanesAreRGB() throws {
        func f32(_ v: Float) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.bigEndian, Array.init) }
        let planes: [[Float]] = [[1, .nan], [0, 0], [0, 1]]  // red, green, blue planes of a 2×1 image
        let bytes = Self.file([Self.card("SIMPLE", "T"), Self.card("BITPIX", "-32"), Self.card("NAXIS", "3"),
                               Self.card("NAXIS1", "2"), Self.card("NAXIS2", "1"), Self.card("NAXIS3", "3")],
                              data: planes.flatMap { $0.flatMap(f32) })
        let image = try FITSDecoder.decode(Data(bytes))
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (0, 0, 255, 255))
    }

    @Test func decodesThroughImageDecoder() throws {
        let bytes = Self.file([Self.card("SIMPLE", "T"), Self.card("BITPIX", "8"), Self.card("NAXIS", "2"),
                               Self.card("NAXIS1", "3"), Self.card("NAXIS2", "1")], data: [1, 2, 3])
        for ext in ["fits", "fit", "fts"] {
            let url = try Fixtures.makeTempDir().appendingPathComponent("a.\(ext)")
            try Data(bytes).write(to: url)
            #expect(ImageFormats.isDecodable(url) && ImageDecoder.displaySize(of: url) == CGSize(width: 3, height: 1))
        }
    }

    @Test func rejectsBadFiles() {
        let cards = [Self.card("SIMPLE", "T"), Self.card("BITPIX", "8"), Self.card("NAXIS", "2"),
                     Self.card("NAXIS1", "2"), Self.card("NAXIS2", "2")]
        #expect(throws: OwnDecodeError.notThisFormat) { try FITSDecoder.decode(Data(Self.file(["SIMPLX  = T"] + cards.dropFirst(), data: [1, 2, 3, 4]))) }
        #expect(throws: OwnDecodeError.truncated) { try FITSDecoder.decode(Data(Self.file(cards, data: [1, 2, 3, 4]).prefix(2883))) }
        #expect(throws: OwnDecodeError.truncated) { try FITSDecoder.decode(Data(Self.file(cards, data: []).prefix(1000))) }
        #expect(throws: OwnDecodeError.unsupported) {
            try FITSDecoder.decode(Data(Self.file(Array(cards.prefix(2)) + [Self.card("NAXIS", "1"), Self.card("NAXIS1", "4")], data: [1, 2, 3, 4])))
        }
        // 65536×4096 claimed with no data: throws before allocating.
        #expect(throws: OwnDecodeError.truncated) {
            try FITSDecoder.decode(Data(Self.file(Array(cards.prefix(3)) + [Self.card("NAXIS1", "65536"), Self.card("NAXIS2", "4096")], data: [])))
        }
    }
}
