import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct JPEGXRDecoderTests {
    /// 2×2 lossless 24-bit BGR, made with jxrlib's encoder: red, lime / blue, white.
    static let rgb = Data(base64Encoded: """
        SUm8ASAAAAAkw91vA07+S7GFPXd2jckNAAAAAAAAAAAIAAG8AQAQAAAACAAAAAK8BAABAAAAAAAAAIC8BAABAAAAAgAAAIG8BAABAAAAAgAAAIK8CwABAAAAAADAQoO8CwABAAAAAADAQsC8BAABAAAAhgAAAMG8BAABAAAA8gEAAAAAAABXTVBIT1RPABFFwHEAAQABYADAAAAMAAAAwAAAAAABAAAACAA8//8AAAEB/Rk1MgAAAQL8hnj5lRwchHTJE2TEcQwsMMtEIZERA1o0n+ZfuvZtOohRtEe+Ilrpe8vDWrUBq0AAAAEDJPd/CVYwmMEjCY0YTADCKxDDCWgwkuIIIMItEIIIDwRNBEthKuNMJLZBhG2ic1BhM/5hMDKmEkEnNDkY2Eq40wktkGEbaJzeEuxBBxCjCXQwiAQRIMIgGEmSCIYghQgg4gHhCMcOjH7HdNhUphM/MJgZUwkhJmgdFvhDxiDCbgQSVGE3AgjgQSUGElBhMMMJJEEdRCeEDwh5p4vg0KHRbQ8X6NCxPF8GhUt7NHeuExwgmDGE5YgjMYT3jCYoYTUihhN+MJLjCWwgjYYRTwQOOognXogmt6QSr8gYSrcMJKoQjZRBOvRBNb0glX5OEZiCfEYQgQT8jCRYgkIIJCiCbYYSEGEcjCMiCMvhCYIYGEq3DCSqEI25RhBBhLcQRwII4GEuhBEYwjcYSaGEaiCJiL8BhA+EywwmHEEwgwmgGE4QgmcGEYjCX4gl4MJihcYQYYSV8JB4FaQTrogmt8glX4LSCddEE1vkEq/DARBFIgnyGEtBhLQQT7jCRIgm2EEtBBK4YSPMF4IVBFg=
        """, options: .ignoreUnknownCharacters)!

    /// 2×2 32-bit BGRA with a planar alpha: red, grey 100 / grey 100 at alpha 128 (both).
    static let rgba = Data(base64Encoded: """
        SUm8ASAAAAAkw91vA07+S7GFPXd2jckPAAAAAAAAAAAKAAG8AQAQAAAACAAAAAK8BAABAAAAAAAAAIC8BAABAAAAAgAAAIG8BAABAAAAAgAAAIK8CwABAAAAAADAQoO8CwABAAAAAADAQsC8BAABAAAAngAAAMG8BAABAAAArAAAAMK8BAABAAAASgEAAMO8BAABAAAAyAEAAAAAAABXTVBIT1RPABFFwHEAAQABYADAAAAMAAAAwAAAAAABAAAACAAq//8AAAEB0ygsLgAAAQKFGUpRlGMYylGNq0tm9a3rKlZSld1fs/zr+q3zWcAAAAEDQysnHGcYIYQIZRhBBnGEAHxkGDHhvNcIsGEKGEajCQgwgowkYMIcMI8GCGEEGEcjHGLxYXhJkYRqMJWjCYkYRYMJmhhHgwl0MIYMIpGEsxhBRhA+AwQUV01QSE9UTwARRcABAAEAAQCAIAgAAAEAAAAGABb//wAAAQEsAAAAAQLREuQLIYQhAAgGACAAAAEDI3glwYGIJeDCIRBEgwiEQSbMIhiCIxhEIh/AbwI0aYRJ8wiVqHZrzqwAY4whAgiIQRCMIkEEQiCJRhEJhC4whAx+AwQc
        """, options: .ignoreUnknownCharacters)!

    @Test func readsTheSize() throws {
        #expect(try JPEGXRDecoder.size(Self.rgb) == (2, 2))
    }

    @Test func decodesLosslessRGB() throws {
        let image = try JPEGXRDecoder.decode(Self.rgb)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (0, 255, 0, 255))
        #expect(image[0, 1] == (0, 0, 255, 255) && image[1, 1] == (255, 255, 255, 255))
        #expect(image.isOpaque)
    }

    @Test func decodesTheAlphaPlane() throws {
        let image = try JPEGXRDecoder.decode(Self.rgba)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (100, 100, 100, 255))
        #expect(image[0, 1] == (100, 100, 100, 128))
    }

    /// Office's HD Photo files are premultiplied BGRA (pixel format GUID ending in 0x10, not 0x0F).
    @Test func undoesPremultipliedAlpha() throws {
        var file = Self.rgba
        #expect(file[0x17] == 0x0F)
        file[0x17] = 0x10
        let image = try JPEGXRDecoder.decode(file)
        #expect(image[1, 0] == (100, 100, 100, 255))
        #expect(image[0, 1] == (199, 199, 199, 128))
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try JPEGXRDecoder.decode(Data("not an image".utf8)) }
        #expect(throws: OwnDecodeError.notThisFormat) { try JPEGXRDecoder.size(Data([0x49, 0x49])) }
        #expect(throws: (any Error).self) { try JPEGXRDecoder.decode(Self.rgb.prefix(200)) }
        var flipped = Self.rgb
        for i in stride(from: 160, to: flipped.count, by: 7) { flipped[i] ^= 0x5A }
        #expect(throws: (any Error).self) { _ = try JPEGXRDecoder.decode(flipped).pixels.count }
    }

    /// 65536×4096 claimed in the bitstream's short header (width and height minus one, at 0x92) with
    /// the data of a 2×2 image: fails before decoding for long or touching a gigabyte.
    @Test func hugeClaimWithoutDataFailsFast() throws {
        var file = Self.rgb
        file.replaceSubrange(0x92..<0x96, with: [0xFF, 0xFF, 0x0F, 0xFF])
        #expect(try JPEGXRDecoder.size(file) == (65536, 4096))
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.truncated) { try JPEGXRDecoder.decode(file) }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    /// 65536 × 65536 claimed in the header: refused as corrupt before anything is allocated.
    @Test func hugeHeaderIsRefused() {
        var data = Self.rgb
        data.replaceSubrange(0x92..<0x96, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: OwnDecodeError.corrupt) { try JPEGXRDecoder.size(data) }
        #expect(throws: OwnDecodeError.corrupt) { try JPEGXRDecoder.decode(data) }
    }

    // Fuzz findings (scripts/fuzz.sh), shrunk: each crashed jxrlib (an assert or an out-of-bounds access).

    /// Hex bytes; `XX*N` is N bytes of XX.
    static func hex(_ text: String) -> Data {
        Data(text.split(whereSeparator: \.isWhitespace).flatMap { token -> [UInt8] in
            let parts = token.split(separator: "*")
            return [UInt8](repeating: UInt8(parts[0], radix: 16)!, count: parts.count > 1 ? Int(parts[1])! : 1)
        })
    }

    /// Throws an `OwnDecodeError` or decodes, within a second.
    func throwsOrDecodes(_ data: Data) {
        let start = ContinuousClock.now
        _ = try? JPEGXRDecoder.size(data)
        do { _ = try JPEGXRDecoder.decode(data) } catch { #expect(error is OwnDecodeError) }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    /// The image header's signature read with strstr, past its 8 bytes.
    @Test func crashInput1Throws() { throwsOrDecodes(Self.hex("49 49 BC 01 20 4E FE 4B")) }

    /// Orientation 255 in the container.
    @Test func crashInput2Throws() {
        throwsOrDecodes(Self.hex("49 49 BC 00 20 00*27 08 00*13 02 BC 00 00 01 00*4 FF"))
    }

    /// A metadata entry of a type jxrlib doesn't read.
    @Test func crashInput3Throws() { throwsOrDecodes(Self.hex("49 49 BC 00 20 00*27 08 00*25 10 01 00 00 08")) }

    /// Bit depth 12 in the image header, an index past jxrlib's tables.
    @Test func crashInput4Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 00 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0D 00*8 08 00 01 BC 00*6 08
            00*63 C0 BC 00 00 01 00 00 00 86 00*19 57 4D 50 48 4F 54 4F 00 11 00 00 BC
            """))
    }

    /// 1 bit per pixel in colour.
    @Test func crashInput5Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 00 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0D 00*8 08 00 01 BC 00*6 08
            00*63 C0 BC 00 00 01 00 00 00 86 00*19 57 4D 50 48 4F 54 4F 00 11 45 C0 00*5 60 00 C0 00 00 0C
            00 00 00 C0 00*4 01 00*6 FF FF 00 00 01 00*60
            """))
    }

    /// A damaged alpha plane header.
    @Test func crashInput6Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 00 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0D 00*8 08 00 01 BC 00*6 08
            00*63 C0 BC 00 00 01 00 00 00 86 00*19 57 4D 50 48 4F 54 4F 00 11 00 C1 00*7 F2
            """))
    }

    /// Internal colour format 5, which has no channels.
    @Test func crashInput7Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 00 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0D 00*8 08 00 01 BC 00*6 08
            00*63 C0 BC 00 00 01 00 00 00 86 00*19 57 4D 50 48 4F 54 4F 00 11 00 C0 71 00*4 BC
            """))
    }

    /// A coefficient run of 15, past the run table.
    @Test func crashInput8Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 00 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0D 00*8 08 00 01 BC 00*6 08
            00*63 C0 BC 00 00 01 00 00 00 86 00*19 57 4D 50 48 4F 54 4F 00 11 45 C0 00 80 00 00 00 60 00 C0
            00 00 0C 00 00 00 C0 00*4 01 00*5 3C FF FF 00 00 01 00*59 01 00*321 C2 44 88 26 D8 00 2D 04 12
            00 61 23 CC
            """))
    }

    /// A frequency-mode low-pass quantizer index past the tile's quantizers, in a 1-bit black and white file
    /// (the codestream attached to upstream's pull request 67).
    @Test func lowpassQuantizerIndexPastTheTileThrows() {
        let data = Self.hex("""
            49 49 BC 01 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 05 00 00 00 00 00 00 00 00 08
            00 01 BC 01 00 10 00 00 00 08 00 00 00 02 BC 04 00 01 00 00 00 00 00 00 00 80 BC 04 00 01 00 00 00
            02 00 00 00 81 BC 04 00 01 00 00 00 02 00 00 00 82 BC 0B 00 01 00 00 00 00 00 C0 42 83 BC 0B 00 01
            00 00 00 00 00 C0 42 C0 BC 04 00 01 00 00 00 86 00 00 00 C1 BC 04 00 01 00 00 00 1F 00 00 00 00 00
            00 00 57 4D 50 48 4F 54 4F 00 11 44 C0 00 00 16 00 00 01 03 00 01 FF FF FF FF 00 00 01 01 0B FF FF
            """)
        #expect(throws: OwnDecodeError.corrupt) { try JPEGXRDecoder.decode(data) }
    }

    /// 16-bit 555 pixels in a black and white file: jxrlib writes them for RGB only.
    @Test func crashInput9Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 01 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 05 00 00 00 00 00 00 00 00 08
            00 01 BC 01 00 10 00 00 00 08 00 00 00 02 BC 04 00 01 00 00 00 00 00 00 00 80 BC 04 00 01 00 00 00
            02 00 00 00 81 BC 04 00 01 00 00 00 02 00 00 00 82 BC 0B 00 01 00 00 00 00 00 C0 42 83 BC 0B 00 01
            00 00 00 00 00 C0 42 C0 BC 04 00 01 00 00 00 86 00 00 00 C1 BC 04 00 01 00 00 00 1F 00 00 00 00 00
            00 00 57 4D 50 48 4F 54 4F 00 11 44 C0 08 00 16 00 00 01 03 00 01 FF FF FF FF 00 00 01 00 16 00 00
            01 03 00 01 FF FF FF FF 00 00 01 01 0B FF FF
            """))
    }

    /// A damaged alpha plane that claims a far larger picture than the image (tens of gigabytes).
    @Test func crashInput10Throws() {
        throwsOrDecodes(Self.hex("""
            49 49 BC 01 20 00 00 00 24 C3 DD 6F 03 4E FE 4B B1 85 3D 77 76 8D C9 0F 00 00 00 00 00 00 00 00 0A
            00 01 BC 01 00 10 00 00 00 08 00 00 00 02 BC 04 00 01 00 00 00 00 00 00 00 80 BC 04 00 01 00 00 00
            02 00 00 00 81 BC 04 00 01 00 00 00 02 00 00 00 82 BC 0B 00 01 00 00 00 00 00 C0 42 83 BC 0B 00 01
            00 00 00 00 00 C0 42 C0 BC 04 00 01 00 00 00 9E 00 00 00 C1 BC 04 00 01 00 00 00 AC 00 00 00 C2 BC
            04 00 01 00 00 00 4A 01 00 00 C3 BC 04 00 01 00 00 00 C8 01 00 00 00 00 00 00 57 4D 50 48 4F 54 4F
            00 11 45 C0 71 00 01 00 01 60 00 C0 00 00 0C 00 00 00 C0 00 00 00 00 01 00 00 00 08 00 2A FF FF 00
            00 01 01 D3 28 2C 2E 00 00 01 02 85 19 4A 51 94 63 18 CA 51 8D AB 4B 66 F5 AD EB 2A 56 52 95 DD 5F
            B3 FC EB FA AD F3 59 C0 00 00 01 03 43 2B 27 1C 67 18 21 84 08 65 18 41 06 71 84 00 7C 64 18 31 E1
            BC D7 08 B0 61 0A 18 46 A3 09 08 30 82 8C 24 60 C2 18 30 8F 06 08 61 04 18 47 23 1C 62 F1 61 78 49
            91 84 6A 30 95 A3 09 89 18 45 83 09 9A 18 47 83 09 74 30 86 0C 22 91 84 B3 18 41 46 10 3E 03 04 14
            57 4D 50 48 4F 54 4F 00 10 3E 03 04 14 57 4D 50 48 4F 54 4F 00 11 45 C0 01 00 01 00 01 00 80 20 08
            00 00 01 00 00 00 06 00 16 FF FF 00 00 01 01 2C 00 00 00 01 02 D1 12 E4 0B 21 84 21 00 08 06 00 20
            00 00 01 03 23 78 25 C1 81 88 25 E0 C2 21 10 44 83 08 84 41 26 CC 22 18 82 23 18 44 22 1F C0 6F 02
            34 69 84 49 F3 08 95 A8 76 6B CE AC 00 63 02 08 88 41 10
            """))
    }

    /// `rgb` with its orientation entry (the IFD's second, at 46) replaced.
    static func rgb(entry: [UInt8]) -> Data {
        var data = rgb
        data.replaceSubrange(46..<58, with: entry)
        return data
    }

    /// Damaged metadata is ignored: a caption whose bytes lie past the end, a camera model without its
    /// closing null. Both still show the picture.
    @Test func damagedMetadataStillDecodes() throws {
        let caption = Self.rgb(entry: [0x9B, 0x9C, 1, 0, 100, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0])
        let model = Self.rgb(entry: [0x10, 0x01, 2, 0, 4, 0, 0, 0] + Array("abcd".utf8))
        #expect(try JPEGXRDecoder.decode(caption).width == 2)
        #expect(try JPEGXRDecoder.decode(model).width == 2)
    }
}
