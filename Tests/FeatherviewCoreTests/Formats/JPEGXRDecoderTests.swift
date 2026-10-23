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
