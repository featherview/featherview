import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BPGDecoderTests {
    /// 16×16, 4:2:0, a vertical gradient from red to blue; made with bellard.org's bpgenc.
    static let gradient: [UInt8] = [
        0x42, 0x50, 0x47, 0xFB, 0x20, 0x00, 0x10, 0x10, 0x00, 0x03, 0x92, 0x47,
        0x40, 0x44, 0x01, 0xC1, 0x90, 0x95, 0x81, 0x12, 0x00, 0x00, 0x01, 0x26,
        0x01, 0xAF, 0x1B, 0x80, 0xF7, 0x71, 0x4A, 0xE0, 0xD0, 0x7B, 0xBF, 0xCC,
        0xDF, 0xFF, 0x9F, 0x33, 0x8F, 0xED, 0xAD, 0xC9, 0xC4, 0x79, 0x40, 0x52,
        0x1A, 0xAB, 0xB6, 0x5F,
    ]

    /// The same gradient with an alpha plane: opaque top half, alpha 128 below.
    static let gradientWithAlpha: [UInt8] = [
        0x42, 0x50, 0x47, 0xFB, 0x30, 0x00, 0x10, 0x10, 0x00, 0x03, 0x92, 0x47,
        0x40, 0x03, 0x92, 0x47, 0x40, 0x44, 0x09, 0xC1, 0x90, 0x95, 0x81, 0x12,
        0x00, 0x00, 0x00, 0x01, 0x44, 0x01, 0xC1, 0x90, 0x95, 0x81, 0x12, 0x00,
        0x00, 0x01, 0x26, 0x09, 0xAE, 0x37, 0xC5, 0x66, 0xB7, 0x44, 0x0B, 0x83,
        0x9F, 0xED, 0x0F, 0x7E, 0x3C, 0x00, 0x00, 0x01, 0x26, 0x01, 0xAF, 0x1B,
        0x80, 0xF7, 0x71, 0x4A, 0xE0, 0xD0, 0x7B, 0xBF, 0xCC, 0xDF, 0xFF, 0x9F,
        0x33, 0x8F, 0xED, 0xAD, 0xC9, 0xC4, 0x79, 0x40, 0x52, 0x1A, 0xAB, 0xB6,
        0x5F,
    ]

    @Test func readsTheSizeFromTheHeader() throws {
        #expect(try BPGDecoder.size(Data(Self.gradient)) == (16, 16))
        // 542 × 8 as multi-byte numbers, nothing after them.
        #expect(try BPGDecoder.size(Data([0x42, 0x50, 0x47, 0xFB, 0x20, 0x00, 0x84, 0x1E, 0x08])) == (542, 8))
    }

    @Test func decodesColour() throws {
        let image = try BPGDecoder.decode(Data(Self.gradient))
        #expect(image.width == 16 && image.height == 16 && image.isOpaque)
        let top = image[0, 0], bottom = image[15, 15]
        #expect(top.r > 230 && top.g < 20 && top.b < 30)
        #expect(bottom.r < 20 && bottom.g < 20 && bottom.b > 230)
    }

    @Test func decodesTheAlphaPlane() throws {
        let image = try BPGDecoder.decode(Data(Self.gradientWithAlpha))
        #expect(image[0, 0].a == 255 && image[0, 0].r > 230)
        #expect(image[15, 15].a == 128 && image[15, 15].b > 230)
    }

    /// The HEVC picture is coded in whole 8-pixel blocks; the header's size crops it.
    @Test func cropsToTheHeaderSize() throws {
        var file = Self.gradient
        file[6] = 15; file[7] = 13
        let image = try BPGDecoder.decode(Data(file))
        #expect(image.width == 15 && image.height == 13)
    }

    @Test func writesExpGolombAndEmulationPrevention() {
        var w = BPGDecoder.BitWriter()
        w.ue(0); w.ue(3); w.u(0, 2)  // 1 00100 00
        #expect(w.bytes == [0b1001_0000])
        var zeros = BPGDecoder.BitWriter()
        zeros.u(0, 16); zeros.u(1, 8)
        #expect(zeros.nal(type: 33) == [0x42, 0x01, 0, 0, 3, 1, 0x80])
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try BPGDecoder.decode(Data("not a picture".utf8)) }
        #expect(throws: OwnDecodeError.truncated) { try BPGDecoder.size(Data(Self.gradient.prefix(7))) }
        #expect(throws: OwnDecodeError.corrupt) { try BPGDecoder.size(Data([0x42, 0x50, 0x47, 0xFB, 0x20, 0x00, 0x80, 0x10, 0x10])) }
        #expect(throws: OwnDecodeError.corrupt) { try BPGDecoder.size(Data([0x42, 0x50, 0x47, 0xFB, 0x20, 0x00, 0x00, 0x10])) }
        var cmyk = Self.gradient
        cmyk[5] = 0x04  // alpha2 without alpha1: the alpha plane is CMYK's W
        #expect(throws: OwnDecodeError.unsupported) { try BPGDecoder.decode(Data(cmyk)) }
    }

    /// HEVC conceals damage: cut or garbled picture data gives either an error or a picture of the
    /// header's size (like a cut JPEG), never a crash.
    @Test func damagedPictureDataIsSafe() {
        var garbled = Self.gradient
        for i in 26..<garbled.count { garbled[i] ^= 0xA5 }
        for file in [Array(Self.gradient.prefix(40)), Array(Self.gradient.prefix(24)), garbled] {
            if let image = try? BPGDecoder.decode(Data(file)) { #expect(image.width == 16 && image.height == 16) }
        }
    }

    /// 65536×4096 claimed with 40 bytes of picture data: fails before ImageIO allocates a gigabyte.
    @Test func hugeClaimWithoutDataFailsFast() {
        var file: [UInt8] = [0x42, 0x50, 0x47, 0xFB, 0x20, 0x00, 0x84, 0x80, 0x00, 0xA0, 0x00]
        file += Self.gradient[8...]
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.truncated) { try BPGDecoder.decode(Data(file)) }
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
