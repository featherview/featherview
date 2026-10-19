import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct WBMPDecoderTests {
    /// 3×2: rows 101 and 010, MSB first.
    static let file: [UInt8] = [0, 0, 3, 2, 0b1010_0000, 0b0100_0000]

    @Test func readsMultiByteSizes() throws {
        let size = try WBMPDecoder.size(Data([0, 0, 0x81, 0x48, 1]))
        #expect(size == (200, 1))
    }

    @Test func bitsAreMostSignificantFirstAndSetMeansWhite() throws {
        let image = try WBMPDecoder.decode(Data(Self.file))
        #expect(image[0, 0].r == 255 && image[1, 0].r == 0 && image[2, 0].r == 255)
        #expect(image[0, 1] == (0, 0, 0, 255) && image[1, 1] == (255, 255, 255, 255) && image[2, 1].r == 0)
    }

    @Test func decodesThroughImageDecoder() throws {
        OwnDecoders.register(WBMPDecoder.format)
        let url = try Fixtures.makeTempDir().appendingPathComponent("t.wbmp")
        try Data(Self.file).write(to: url)
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 3 && image.height == 2)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try WBMPDecoder.decode(Data([1, 0, 3, 2])) }
        #expect(throws: OwnDecodeError.truncated) { try WBMPDecoder.decode(Data(Self.file.dropLast())) }
        #expect(throws: OwnDecodeError.truncated) { try WBMPDecoder.size(Data([0, 0, 0x81])) }
        #expect(throws: OwnDecodeError.corrupt) { try WBMPDecoder.size(Data([0, 0, 0, 2])) }
        #expect(throws: OwnDecodeError.corrupt) { try WBMPDecoder.size(Data([0, 0] + [UInt8](repeating: 0xFF, count: 20))) }
    }

    /// 65536×4096 claimed with no pixel data: must throw before allocating 1 GiB of RGBA.
    @Test func hugeClaimWithoutDataFailsFast() {
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.truncated) { try WBMPDecoder.decode(Data([0, 0, 0x84, 0x80, 0x00, 0xA0, 0x00])) }
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }
}
