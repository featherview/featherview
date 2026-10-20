import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct XWDDecoderTests {
    static func be32(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(v >> $0 & 0xFF) } }

    /// An XWD file version 7, Z pixmap: 25 header fields, the window name, the colormap, the pixels.
    static func file(width: Int, height: Int, depth: Int, bitsPerPixel: Int, bytesPerLine: Int, visualClass: Int,
                     masks: (Int, Int, Int) = (0, 0, 0), byteOrder: Int = 1, bitOrder: Int = 1,
                     colors: [(pixel: Int, r: Int, g: Int, b: Int)] = [], pixels: [UInt8]) -> [UInt8] {
        let name = Array("w\0".utf8)
        let fields = [100 + name.count, 7, 2, depth, width, height, 0, byteOrder, 32, bitOrder, 32, bitsPerPixel,
                      bytesPerLine, visualClass, masks.0, masks.1, masks.2, 8, colors.count, colors.count,
                      width, height, 0, 0, 0]
        let map: [UInt8] = colors.flatMap { c -> [UInt8] in
            let rgb: [UInt8] = [c.r, c.g, c.b].flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
            return be32(c.pixel) + rgb + [7, 0]
        }
        return fields.flatMap(be32) + name + map + pixels
    }

    @Test func trueColor32BitUsesTheMasks() throws {
        // xRGB, most significant byte first: red, then blue.
        let bytes = Self.file(width: 2, height: 1, depth: 24, bitsPerPixel: 32, bytesPerLine: 8, visualClass: 4,
                              masks: (0xFF0000, 0x00FF00, 0x0000FF), pixels: [0, 255, 0, 0, 0, 0, 0, 255])
        #expect(try XWDDecoder.size(Data(bytes)) == (2, 1))
        let image = try XWDDecoder.decode(Data(bytes))
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (0, 0, 255, 255))
    }

    @Test func trueColor16BitLeastSignificantByteFirst() throws {
        // RGB565 0xF800 (red) and 0x07E0 (green), little-endian, rows padded to 4 bytes.
        let bytes = Self.file(width: 2, height: 2, depth: 16, bitsPerPixel: 16, bytesPerLine: 4, visualClass: 4,
                              masks: (0xF800, 0x07E0, 0x001F), byteOrder: 0,
                              pixels: [0x00, 0xF8, 0xE0, 0x07, 0x1F, 0x00, 0xFF, 0xFF])
        let image = try XWDDecoder.decode(Data(bytes))
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (0, 255, 0, 255))
        #expect(image[0, 1] == (0, 0, 255, 255) && image[1, 1] == (255, 255, 255, 255))
    }

    @Test func pseudoColor8BitLooksUpTheColormapByPixelValue() throws {
        let bytes = Self.file(width: 3, height: 1, depth: 8, bitsPerPixel: 8, bytesPerLine: 4, visualClass: 3,
                              colors: [(5, 0xFFFF, 0x8000, 0), (9, 0, 0, 0xFFFF)], pixels: [5, 9, 5, 0])
        let image = try XWDDecoder.decode(Data(bytes))
        #expect(image[0, 0] == (255, 128, 0, 255) && image[1, 0] == (0, 0, 255, 255) && image[2, 0].r == 255)
    }

    @Test func oneBitUsesTheColormapAndBitOrder() throws {
        // Pixels 1 0 1, least significant bit first; pixel 0 white, 1 black.
        let bytes = Self.file(width: 3, height: 1, depth: 1, bitsPerPixel: 1, bytesPerLine: 4, visualClass: 0,
                              bitOrder: 0, colors: [(0, 0xFFFF, 0xFFFF, 0xFFFF), (1, 0, 0, 0)], pixels: [0b101, 0, 0, 0])
        let image = try XWDDecoder.decode(Data(bytes))
        #expect(image[0, 0].r == 0 && image[1, 0].r == 255 && image[2, 0].r == 0)
    }

    @Test func decodesThroughImageDecoder() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.xwd")
        try Data(Self.file(width: 1, height: 1, depth: 24, bitsPerPixel: 32, bytesPerLine: 4, visualClass: 4,
                           masks: (0xFF0000, 0xFF00, 0xFF), pixels: [0, 1, 2, 3])).write(to: url)
        #expect(ImageFormats.isDecodable(url) && ImageDecoder.displaySize(of: url) == CGSize(width: 1, height: 1))
    }

    @Test func rejectsBadFiles() {
        let good = Self.file(width: 2, height: 1, depth: 24, bitsPerPixel: 32, bytesPerLine: 8, visualClass: 4,
                             masks: (0xFF0000, 0xFF00, 0xFF), pixels: [UInt8](repeating: 0, count: 8))
        var version6 = good; version6[7] = 6
        #expect(throws: OwnDecodeError.notThisFormat) { try XWDDecoder.decode(Data(version6)) }
        #expect(throws: OwnDecodeError.truncated) { try XWDDecoder.decode(Data(good.dropLast())) }
        var xyPixmap = good; xyPixmap[11] = 1
        #expect(throws: OwnDecodeError.unsupported) { try XWDDecoder.decode(Data(xyPixmap)) }
        // 65536×4096 claimed with no pixels: throws before allocating.
        let huge = Self.file(width: 65536, height: 4096, depth: 24, bitsPerPixel: 32, bytesPerLine: 262_144,
                             visualClass: 4, masks: (0xFF0000, 0xFF00, 0xFF), pixels: [])
        #expect(throws: OwnDecodeError.truncated) { try XWDDecoder.decode(Data(huge)) }
    }
}
