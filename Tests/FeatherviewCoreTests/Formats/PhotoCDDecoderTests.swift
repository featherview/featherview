import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PhotoCDDecoderTests {
    /// A file with only the header and the Base image (768×512): every luma byte 100, chroma neutral,
    /// except the top-left 2×2 block, which is luma 150 over 0 below, with blue chroma.
    static let file: Data = {
        let y: UInt8 = 100
        var bytes = [UInt8](repeating: 0, count: 0x30000 + 768 * 512 * 3 / 2)
        bytes.replaceSubrange(0x800..<0x807, with: Array("PCD_IPI".utf8))
        for pair in 0..<256 {
            let row = 0x30000 + pair * 768 * 3
            for x in 0..<768 {
                bytes[row + x] = y
                bytes[row + 768 + x] = y
            }
            for x in 0..<384 {
                bytes[row + 1536 + x] = 156
                bytes[row + 1920 + x] = 137
            }
        }
        bytes[0x30000] = 150; bytes[0x30001] = 150
        bytes[0x30000 + 768] = 0; bytes[0x30000 + 769] = 0
        bytes[0x30000 + 1536] = 255  // C1 (blue difference) up
        return Data(bytes)
    }()

    static func rotated(_ rotation: UInt8) -> Data {
        var bytes = file
        bytes[0xE02] = rotation
        return bytes
    }

    @Test func sizeIsBaseAndSwapsWhenRotated() throws {
        #expect(try PhotoCDDecoder.size(Self.file) == (768, 512))
        #expect(try PhotoCDDecoder.size(Self.rotated(0x4B)) == (512, 768))
        #expect(try PhotoCDDecoder.size(Self.rotated(2)) == (768, 512))
    }

    @Test func neutralChromaIsGrey() throws {
        let image = try PhotoCDDecoder.decode(Self.file)
        let pixel = image[100, 100]
        #expect(pixel.r == pixel.g && pixel.g == pixel.b && pixel.a == 255)
        #expect(pixel.r > 120 && pixel.r < 150)
    }

    @Test func twoLumaRowsShareOneChromaRow() throws {
        let image = try PhotoCDDecoder.decode(Self.file)
        let top = image[1, 0], bottom = image[0, 1]
        #expect(top.b > top.r && top.b > 200)
        #expect(bottom.r == 0 && bottom.b > 0)  // same blue chroma on black luma
        #expect(image[2, 0].r == image[2, 0].b)  // the next chroma sample is neutral again
    }

    @Test func rotationTurnsTheImageUpright() throws {
        // 1 turns a quarter counter-clockwise: the stored top-left corner ends up bottom-left.
        #expect(try PhotoCDDecoder.decode(Self.rotated(1))[0, 767].b > 200)
        #expect(try PhotoCDDecoder.decode(Self.rotated(2))[767, 511].b > 200)
        #expect(try PhotoCDDecoder.decode(Self.rotated(3))[511, 0].b > 200)
    }

    @Test func rejectsBadFiles() {
        var other = Self.file
        other[0x800] = UInt8(ascii: "X")
        #expect(throws: OwnDecodeError.notThisFormat) { try PhotoCDDecoder.decode(other) }
        #expect(throws: OwnDecodeError.truncated) { try PhotoCDDecoder.decode(Self.file.prefix(0x30000 + 1000)) }
        #expect(throws: OwnDecodeError.notThisFormat) { try PhotoCDDecoder.size(Data([0, 1, 2])) }
        #expect(throws: OwnDecodeError.truncated) { try PhotoCDDecoder.decode(Self.file.prefix(0x1000)) }  // only a header
    }
}
