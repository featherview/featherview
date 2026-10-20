import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FarbfeldDecoderTests {
    /// 2×1: opaque red, then half-transparent white; 16 bits per channel, big-endian.
    static let file: [UInt8] = Array("farbfeld".utf8) + [0, 0, 0, 2, 0, 0, 0, 1]
        + [0xFF, 0xFF, 0, 0, 0, 0, 0xFF, 0xFF] + [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x00]

    @Test func decodesSixteenBitRGBA() throws {
        #expect(try FarbfeldDecoder.size(Data(Self.file)) == (2, 1))
        let image = try FarbfeldDecoder.decode(Data(Self.file))
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (255, 255, 255, 128))
    }

    @Test func decodesThroughImageDecoder() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.ff")
        try Data(Self.file).write(to: url)
        #expect(ImageFormats.isDecodable(url))
        #expect(try ImageDecoder.decode(url).width == 2)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try FarbfeldDecoder.decode(Data("farbfelt".utf8 + Self.file.dropFirst(8))) }
        #expect(throws: OwnDecodeError.truncated) { try FarbfeldDecoder.decode(Data(Self.file.dropLast())) }
        #expect(throws: OwnDecodeError.corrupt) { try FarbfeldDecoder.size(Data(Array("farbfeld".utf8) + [0, 0, 0, 0, 0, 0, 0, 1])) }
        // 65536×4096 claimed with no pixels: throws before allocating.
        #expect(throws: OwnDecodeError.truncated) { try FarbfeldDecoder.decode(Data(Array("farbfeld".utf8) + [0, 1, 0, 0, 0, 0, 0x10, 0])) }
    }
}
