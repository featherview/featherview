import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct QOICodecTests {
    /// 6×1: every op once, each pixel compared to the one before (the first to opaque black).
    static let tiny: RGBAImage = {
        var image = RGBAImage(width: 6, height: 1)
        image[0, 0] = (1, 1, 1, 255)
        image[1, 0] = (11, 10, 12, 255)
        image[2, 0] = (11, 10, 12, 255)
        image[3, 0] = (1, 1, 1, 255)
        image[4, 0] = (200, 0, 0, 128)
        image[5, 0] = (200, 0, 0, 128)
        return image
    }()

    static let tinyBytes: [UInt8] = Array("qoif".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 4, 0]
        + [0x7F]                            // DIFF +1 +1 +1: 0x40 | 3<<4 | 3<<2 | 3
        + [0xA9, 0x9A]                      // LUMA dg 9, dr-dg 1, db-dg 2: 0x80 | 41, (1+8)<<4 | (2+8)
        + [0xC0]                            // RUN 1 (stored as length - 1)
        + [0x04]                            // INDEX 4: (1*3 + 1*5 + 1*7 + 255*11) % 64
        + [0xFF, 200, 0, 0, 128]            // RGBA, alpha changed
        + [0xC0]                            // RUN 1, flushed at the last pixel
        + [0, 0, 0, 0, 0, 0, 0, 1]          // end marker

    static func noise(width: Int, height: Int) -> RGBAImage {
        var state: UInt32 = 12345
        var image = RGBAImage(width: width, height: height)
        for i in image.pixels.indices {
            state = state &* 1_103_515_245 &+ 12345
            // Few distinct values, so runs, index hits and small diffs happen, not only RGB/RGBA ops.
            image.pixels[i] = UInt8(truncatingIfNeeded: (state >> 16) % 4) &* 3 &+ (i % 4 == 3 ? 240 : 100)
        }
        return image
    }

    @Test func encodesGoldenBytes() {
        #expect(Array(QOICodec.encode(Self.tiny)) == Self.tinyBytes)
    }

    @Test func decodesGoldenBytes() throws {
        #expect(try QOICodec.decode(Data(Self.tinyBytes)) == Self.tiny)
    }

    @Test func readsSizeFromHeader() throws {
        let size = try QOICodec.size(Data(Self.tinyBytes.prefix(14)))
        #expect(size.width == 6 && size.height == 1)
    }

    @Test func roundTrips() throws {
        let image = Self.noise(width: 17, height: 9)
        #expect(try QOICodec.decode(QOICodec.encode(image)) == image)
    }

    @Test func diffWrapsAround() throws {
        // From opaque black: 255 is a diff of -1, and 255 -> 0 a diff of +1 (arithmetic wraps).
        var image = RGBAImage(width: 2, height: 1)
        image[0, 0] = (255, 255, 255, 255)
        let bytes: [UInt8] = Array("qoif".utf8) + [0, 0, 0, 2, 0, 0, 0, 1, 4, 0]
            + [0x55, 0x7F] + [0, 0, 0, 0, 0, 0, 0, 1]
        #expect(Array(QOICodec.encode(image)) == bytes)
        #expect(try QOICodec.decode(Data(bytes)) == image)
    }

    @Test func hugeHeaderWithoutDataThrowsBeforeAllocating() {
        // 65,536 × 4,096 claims a gigabyte of pixels; 62 per byte is the most QOI can pack.
        let bytes: [UInt8] = Array("qoif".utf8) + [0, 1, 0, 0, 0, 0, 16, 0, 4, 0] + [0xFD, 0xFD]
        #expect(throws: OwnDecodeError.truncated) { try QOICodec.decode(Data(bytes)) }
    }

    @Test func toleratesMissingEndMarker() throws {
        #expect(try QOICodec.decode(Data(Self.tinyBytes.dropLast(8))) == Self.tiny)
    }

    @Test func truncatedThrows() {
        #expect(throws: OwnDecodeError.truncated) { try QOICodec.decode(Data(Self.tinyBytes.prefix(20))) }
        #expect(throws: OwnDecodeError.truncated) { try QOICodec.size(Data(Self.tinyBytes.prefix(10))) }
    }

    @Test func badMagicThrows() {
        var bytes = Self.tinyBytes
        bytes[0] = UInt8(ascii: "x")
        #expect(throws: OwnDecodeError.notThisFormat) { try QOICodec.decode(Data(bytes)) }
    }

    @Test(arguments: [0, 70000]) func absurdSizeThrows(width: Int) {
        var bytes = Self.tinyBytes
        bytes.replaceSubrange(4..<8, with: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: width >> $0) })
        #expect(throws: OwnDecodeError.corrupt) { try QOICodec.size(Data(bytes)) }
    }
}
