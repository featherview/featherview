import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SunRasterDecoderTests {
    static func be32(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }

    /// Header + colormap + body, as a file holds them.
    static func ras(width: Int, height: Int, depth: Int, type: Int = 1, map: [UInt8] = [], body: [UInt8]) -> Data {
        let header = [0x59A6_6A95, width, height, depth, body.count, type, map.isEmpty ? 0 : 1, map.count]
        return Data(header.flatMap(be32) + map + body)
    }

    @Test func eightBitWithColormap() throws {
        // Two entries: reds, then greens, then blues. A row of 2 bytes is already 16-bit aligned.
        let data = Self.ras(width: 2, height: 1, depth: 8, map: [10, 20, 30, 40, 50, 60], body: [1, 0])
        let image = try SunRasterDecoder.decode(data)
        #expect(image[0, 0] == (20, 40, 60, 255))
        #expect(image[1, 0] == (10, 30, 50, 255))
        #expect(try SunRasterDecoder.size(data) == (2, 1))
    }

    @Test func twentyFourBitIsBGRUnlessTypeRGB() throws {
        let body: [UInt8] = [1, 2, 3, 0]  // one pixel, padded to 4 bytes
        #expect(try SunRasterDecoder.decode(Self.ras(width: 1, height: 1, depth: 24, body: body))[0, 0] == (3, 2, 1, 255))
        #expect(try SunRasterDecoder.decode(Self.ras(width: 1, height: 1, depth: 24, type: 3, body: body))[0, 0] == (1, 2, 3, 255))
    }

    @Test func thirtyTwoBitSkipsThePadByte() throws {
        let image = try SunRasterDecoder.decode(Self.ras(width: 1, height: 1, depth: 32, body: [0, 1, 2, 3]))
        #expect(image[0, 0] == (3, 2, 1, 255))
    }

    @Test func runLengthWithEscapedLiteral() throws {
        // 0x80 0x00 is one 0x80; 0x80 0x02 0x07 is three 7s.
        let data = Self.ras(width: 4, height: 1, depth: 8, type: 2, body: [0x80, 0x00, 0x80, 0x02, 0x07])
        let image = try SunRasterDecoder.decode(data)
        #expect(image[0, 0] == (128, 128, 128, 255))
        #expect((1..<4).allSatisfy { image[$0, 0] == (7, 7, 7, 255) })
    }

    @Test func oneBitRowsArePaddedTo16Bits() throws {
        // 3 pixels per row in 2 bytes; set bits are black, padding bits are ignored.
        let data = Self.ras(width: 3, height: 2, depth: 1, body: [0b1010_0000, 0xFF, 0b0100_0000, 0xFF])
        let image = try SunRasterDecoder.decode(data)
        #expect(image[0, 0] == (0, 0, 0, 255) && image[1, 0] == (255, 255, 255, 255) && image[2, 0] == (0, 0, 0, 255))
        #expect(image[0, 1] == (255, 255, 255, 255) && image[1, 1] == (0, 0, 0, 255))
    }

    @Test func decodesThroughImageDecoder() throws {
        OwnDecoders.register(SunRasterDecoder.format)
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.ras")
        try Self.ras(width: 2, height: 1, depth: 8, body: [0, 255]).write(to: url)
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image.width == 2 && image[1, 0] == (255, 255, 255, 255))
    }

    @Test func badFilesThrow() {
        #expect(throws: OwnDecodeError.truncated) {
            try SunRasterDecoder.decode(Self.ras(width: 4, height: 4, depth: 8, body: [1, 2]))
        }
        #expect(throws: OwnDecodeError.truncated) {  // RLE run cut short
            try SunRasterDecoder.decode(Self.ras(width: 4, height: 1, depth: 8, type: 2, body: [0x80, 0x05]))
        }
        #expect(throws: OwnDecodeError.corrupt) { try SunRasterDecoder.decode(Self.ras(width: 0, height: 1, depth: 8, body: [])) }
        #expect(throws: OwnDecodeError.unsupported) { try SunRasterDecoder.decode(Self.ras(width: 1, height: 1, depth: 4, body: [0, 0])) }
        #expect(throws: OwnDecodeError.unsupported) { try SunRasterDecoder.decode(Self.ras(width: 1, height: 1, depth: 8, type: 5, body: [0, 0])) }
        #expect(throws: OwnDecodeError.notThisFormat) { try SunRasterDecoder.decode(Data(repeating: 0, count: 64)) }
    }
}
