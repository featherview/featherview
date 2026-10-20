import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PhotoCDDecoderTests {
    /// A file with only the header and the Base image (768×512): every luma byte `y`, chroma neutral,
    /// except the top-left 2×2 block, which is luma 150 over 0 below, with blue chroma.
    static func file(rotation: UInt8 = 0, y: UInt8 = 100) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x30000 + 768 * 512 * 3 / 2)
        bytes.replaceSubrange(0x800..<0x807, with: Array("PCD_IPI".utf8))
        bytes[0xE02] = rotation
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
    }

    @Test func sizeIsBaseAndSwapsWhenRotated() throws {
        #expect(try PhotoCDDecoder.size(Self.file()) == (768, 512))
        #expect(try PhotoCDDecoder.size(Self.file(rotation: 0x4B)) == (512, 768))
        #expect(try PhotoCDDecoder.size(Self.file(rotation: 2)) == (768, 512))
    }

    @Test func neutralChromaIsGrey() throws {
        let image = try PhotoCDDecoder.decode(Self.file())
        let pixel = image[100, 100]
        #expect(pixel.r == pixel.g && pixel.g == pixel.b && pixel.a == 255)
        #expect(pixel.r > 120 && pixel.r < 150)
    }

    @Test func twoLumaRowsShareOneChromaRow() throws {
        let image = try PhotoCDDecoder.decode(Self.file())
        let top = image[1, 0], bottom = image[0, 1]
        #expect(top.b > top.r && top.b > 200)
        #expect(bottom.r == 0 && bottom.b > 0)  // same blue chroma on black luma
        #expect(image[2, 0].r == image[2, 0].b)  // the next chroma sample is neutral again
    }

    @Test func rotationTurnsTheImageUpright() throws {
        // 1 turns a quarter counter-clockwise: the stored top-left corner ends up bottom-left.
        #expect(try PhotoCDDecoder.decode(Self.file(rotation: 1))[0, 767].b > 200)
        #expect(try PhotoCDDecoder.decode(Self.file(rotation: 2))[767, 511].b > 200)
        #expect(try PhotoCDDecoder.decode(Self.file(rotation: 3))[511, 0].b > 200)
    }

    @Test func decodesThroughImageDecoder() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("img0001.pcd")
        try Self.file().write(to: url)
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 768 && image.height == 512)
    }

    @Test func rejectsBadFiles() {
        var other = Self.file()
        other[0x800] = UInt8(ascii: "X")
        #expect(throws: OwnDecodeError.notThisFormat) { try PhotoCDDecoder.decode(other) }
        #expect(throws: OwnDecodeError.truncated) { try PhotoCDDecoder.decode(Self.file().prefix(0x30000 + 1000)) }
        #expect(throws: OwnDecodeError.notThisFormat) { try PhotoCDDecoder.size(Data([0, 1, 2])) }
    }

    /// Only a header: fails before allocating the image.
    @Test func headerWithoutDataFailsFast() {
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.truncated) { try PhotoCDDecoder.decode(Self.file().prefix(0x1000)) }
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }
}
