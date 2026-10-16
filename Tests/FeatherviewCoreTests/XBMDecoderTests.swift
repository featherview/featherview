import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct XBMDecoderTests {
    static let file = """
        /* a 3×2 test bitmap */
        #define t_width 3
        #define t_height 2
        static unsigned char t_bits[] = {
           0x05, 0x02, };
        """

    @Test func readsSizeFromTheDefines() throws {
        let size = try XBMDecoder.size(Data(Self.file.utf8))
        #expect(size == (3, 2))
    }

    @Test func bitsAreLeastSignificantFirstAndSetMeansBlack() throws {
        let image = try XBMDecoder.decode(Data(Self.file.utf8))
        let black: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255), white: (UInt8, UInt8, UInt8, UInt8) = (255, 255, 255, 255)
        #expect(image[0, 0] == black && image[1, 0] == white && image[2, 0] == black)
        #expect(image[0, 1] == white && image[1, 1] == black && image[2, 1] == white)
    }

    @Test func x10FilesUseSixteenBitWords() throws {
        let text = "#define t_width 17\n#define t_height 1\nstatic short t_bits[] = { 0x8000, 0x0001 };"
        let image = try XBMDecoder.decode(Data(text.utf8))
        #expect(image[15, 0].r == 0 && image[16, 0].r == 0 && image[0, 0].r == 255)
    }

    @Test func decodesThroughImageDecoder() throws {
        OwnDecoders.register(XBMDecoder.format)
        let url = try Fixtures.makeTempDir().appendingPathComponent("t.xbm")
        try Data(Self.file.utf8).write(to: url)
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 3 && image.height == 2)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try XBMDecoder.decode(Data("hello".utf8)) }
        let missing = Self.file.replacingOccurrences(of: "0x05, 0x02,", with: "0x05")
        #expect(throws: OwnDecodeError.truncated) { try XBMDecoder.decode(Data(missing.utf8)) }
        let tooBig = Self.file.replacingOccurrences(of: "0x02", with: "0x100")
        #expect(throws: OwnDecodeError.corrupt) { try XBMDecoder.decode(Data(tooBig.utf8)) }
        let garbage = Self.file.replacingOccurrences(of: "0x02", with: "zz")
        #expect(throws: OwnDecodeError.corrupt) { try XBMDecoder.decode(Data(garbage.utf8)) }
        let huge = Self.file.replacingOccurrences(of: "t_width 3", with: "t_width 99999999999999999999999")
        #expect(throws: OwnDecodeError.corrupt) { try XBMDecoder.size(Data(huge.utf8)) }
    }

    @Test func shortInTheNameIsNotX10() throws {
        let text = """
            #define short_arrow_width 16
            #define short_arrow_height 2
            static unsigned char short_arrow_bits[] = { 0xFF, 0x00, 0x00, 0xFF };
            """
        let image = try XBMDecoder.decode(Data(text.utf8))
        #expect(image[0, 0].r == 0 && image[15, 0].r == 255 && image[0, 1].r == 255 && image[15, 1].r == 0)
    }
}
