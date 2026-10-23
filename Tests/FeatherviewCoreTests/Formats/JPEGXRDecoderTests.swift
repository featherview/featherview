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
}
