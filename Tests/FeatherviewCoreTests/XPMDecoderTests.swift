import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct XPMDecoderTests {
    static let file = """
        /* XPM */
        static char *t[] = {
        /* width height ncolors cpp */
        "3 2 5 1",
        "  c None",
        ". c #FF0000",
        "X s blue_sym c #00F",
        "o m white c gray100",
        "q c #00008000FFFF",
        /* pixels */
        "X. ",
        "o.q"
        };
        """

    @Test func readsSizeFromTheFirstString() throws {
        let size = try XPMDecoder.size(Data(Self.file.utf8))
        #expect(size == (3, 2))
    }

    @Test func mapsEveryColourForm() throws {
        let image = try XPMDecoder.decode(Data(Self.file.utf8))
        #expect(image[0, 0] == (0, 0, 255, 255))     // #RGB, after a symbolic key
        #expect(image[1, 0] == (255, 0, 0, 255))     // #RRGGBB
        #expect(image[2, 0].a == 0)                  // None
        #expect(image[0, 1] == (255, 255, 255, 255)) // grayNN, the colour key beats mono
        #expect(image[2, 1] == (0, 128, 255, 255))   // #RRRRGGGGBBBB
    }

    @Test func namesAndUnknownNames() throws {
        let text = #""2 1 2 2", "aac yellow", "bbc no such colour", "aabb""#
        let image = try XPMDecoder.decode(Data(text.utf8))
        #expect(image[0, 0] == (255, 255, 0, 255))
        #expect(image[1, 0] == (0, 0, 0, 255))
    }

    @Test func decodesThroughImageDecoder() throws {
        OwnDecoders.register(XPMDecoder.format)
        let url = try Fixtures.makeTempDir().appendingPathComponent("t.xpm")
        try Data(Self.file.utf8).write(to: url)
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 3 && image.height == 2)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: OwnDecodeError.notThisFormat) { try XPMDecoder.decode(Data("not an image".utf8)) }
        let noLastRow = Self.file.replacingOccurrences(of: "\"o.q\"", with: "")
        #expect(throws: OwnDecodeError.truncated) { try XPMDecoder.decode(Data(noLastRow.utf8)) }
        let shortRow = Self.file.replacingOccurrences(of: "\"o.q\"", with: "\"o.\"")
        #expect(throws: OwnDecodeError.truncated) { try XPMDecoder.decode(Data(shortRow.utf8)) }
        let unknownPixel = Self.file.replacingOccurrences(of: "\"o.q\"", with: "\"o.Z\"")
        #expect(throws: OwnDecodeError.corrupt) { try XPMDecoder.decode(Data(unknownPixel.utf8)) }
        let hugeColors = Self.file.replacingOccurrences(of: "3 2 5 1", with: "3 2 9223372036854775807 1")
        #expect(throws: OwnDecodeError.truncated) { try XPMDecoder.decode(Data(hugeColors.utf8)) }
        let overflow = Self.file.replacingOccurrences(of: "3 2 5 1", with: "99999999999999999999 2 5 1")
        #expect(throws: OwnDecodeError.corrupt) { try XPMDecoder.size(Data(overflow.utf8)) }
    }

    /// 65536×4096 claimed with empty rows: must throw before allocating 1 GiB of RGBA.
    @Test func hugeClaimWithShortRowsFailsFast() {
        let text = #""65536 4096 1 1", "a c black", "# + String(repeating: #""", "#, count: 4096)
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.truncated) { try XPMDecoder.decode(Data(text.utf8)) }
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }

    @Test func sizeReadsOnlyTheHeader() throws {
        let row = "\"" + String(repeating: "..", count: 4096) + "\",\n"
        let text = "static char *big[] = {\n\"4096 4096 1 2\",\n\".. c #FF0000\",\n" + String(repeating: row, count: 4096) + "};\n"
        let data = Data(text.utf8)  // 33 MB
        let start = ContinuousClock.now
        #expect(try XPMDecoder.size(data) == (4096, 4096))
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}
