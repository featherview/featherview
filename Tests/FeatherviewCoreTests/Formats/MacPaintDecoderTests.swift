import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct MacPaintDecoderTests {
    /// PackBits for one 72-byte row: `bytes` as a literal run when given, else 72 zero bytes as a repeat run.
    static func row(_ bytes: [UInt8]? = nil) -> [UInt8] {
        guard let bytes else { return [UInt8(bitPattern: -71), 0] }
        return [UInt8(bytes.count - 1)] + bytes + [UInt8(bitPattern: Int8(-(72 - bytes.count - 1))), 0]
    }

    /// 576×720; row 0 starts with pixels 1 0 1 1 (1 = black), the rest white.
    static func file(macBinary: Bool = false) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 512)
        header[3] = 2  // version
        var bytes = header + row([0b1011_0000]) + (1..<720).flatMap { _ in row() }
        if macBinary {
            var mb = [UInt8](repeating: 0, count: 128)
            mb[1] = 4; mb.replaceSubrange(2..<6, with: Array("test".utf8))
            mb.replaceSubrange(65..<69, with: Array("PNTG".utf8)); mb.replaceSubrange(69..<73, with: Array("MPNT".utf8))
            bytes = mb + bytes
        }
        return bytes
    }

    @Test(arguments: [false, true])
    func decodesOneBitRowsBlackOnWhite(macBinary: Bool) throws {
        let image = try MacPaintDecoder.decode(Data(Self.file(macBinary: macBinary)))
        #expect(image.width == 576 && image.height == 720)
        #expect(image[0, 0] == (0, 0, 0, 255) && image[1, 0] == (255, 255, 255, 255))
        #expect(image[2, 0].r == 0 && image[3, 0].r == 0 && image[4, 0].r == 255 && image[575, 719].r == 255)
    }

    @Test func decodesThroughImageDecoder() throws {
        for ext in ["mac", "pntg", "pnt"] {
            let url = try Fixtures.makeTempDir().appendingPathComponent("a.\(ext)")
            try Data(Self.file()).write(to: url)
            #expect(ImageFormats.isDecodable(url))
            #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 576, height: 720))
        }
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.truncated) { try MacPaintDecoder.decode(Data(Self.file().dropLast(2))) }
        #expect(throws: OwnDecodeError.truncated) { try MacPaintDecoder.decode(Data([UInt8](repeating: 0, count: 100))) }
        #expect(throws: OwnDecodeError.notThisFormat) {
            var bytes = Self.file(); bytes[3] = 9; try MacPaintDecoder.decode(Data(bytes))
        }
    }
}
