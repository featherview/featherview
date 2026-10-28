import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSBTests {
    @Test func psbIsDecodable() {
        #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/x/a.psb")))
        #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/x/A.PSB")))
    }

    // 3 × 2, row by row: red, green, blue / white, black, yellow
    static let colours: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255), (0, 0, 0), (255, 255, 0)]

    static func minimalPSB() -> [UInt8] {
        func be(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        var bytes = Array("8BPS".utf8) + be(2, 2) + [UInt8](repeating: 0, count: 6)
        bytes += be(3, 2) + be(2, 4) + be(3, 4) + be(8, 2) + be(3, 2)  // channels, height, width, depth, RGB
        bytes += be(0, 4) + be(0, 4) + be(0, 8)  // colour mode data, image resources, layer and mask info (8 bytes in PSB)
        bytes += be(0, 2)  // raw
        bytes += colours.map(\.0) + colours.map(\.1) + colours.map(\.2)
        return bytes
    }

    @Test func decodesAHandBuiltPSB() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.psb")
        try Data(Self.minimalPSB()).write(to: url)
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image.width == 3 && image.height == 2)
        for (i, c) in Self.colours.enumerated() {
            let p = image[i % 3, i / 3]
            #expect(abs(Int(p.r) - Int(c.0)) <= 2 && abs(Int(p.g) - Int(c.1)) <= 2 && abs(Int(p.b) - Int(c.2)) <= 2, "pixel \(i): \(p)")
        }
        #expect(ImageInfo.read(url).picture.dimensions?.hasPrefix("3 × 2 · ") == true)
    }

    @Test(.enabled(if: SampleCorpus.isAvailable)) func psbCorpusMatchesReferences() throws {
        let folder = try #require(SampleCorpus.root).appendingPathComponent("psb")
        let knownLimits: Set = ["kimg_mch3-8bits.psb", "kimg_mch3-16bits.psb", "gen_im_rgba8_zip.psb"]
        // ImageIO and ImageMagick (which made the references) render these differently, not wrongly:
        // CMYK through a CMYK profile vs. a naive formula, grey with a different gamma (spec: PSB).
        let tolerance = ["gen_im_cmyk8_rle.psb": 8.0, "gen_im_cmyk16_raw.psb": 8, "psdtools_gray0.psb": 3]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "psb" }
        #expect(!files.isEmpty)
        for file in files {
            let name = file.lastPathComponent
            if knownLimits.contains(name) {
                #expect(throws: (any Error).self, "\(name)") { try ImageDecoder.decode(file) }
                continue
            }
            let decoded = try ImageDecoder.decode(file)
            guard name != "pyaep_8bits.psb" else { continue }  // its stored composite isn't the real image
            let image = try #require(RGBAImage(decoded))
            let reference = try #require(RGBAImage(try ImageDecoder.decode(SampleCorpus.reference(for: file))))
            let difference = SampleCorpus.difference(image, reference)
            if name == "psdtools_transparentbg-gimp.psb" {
                // Known limit (spec: PSB): ImageIO reads GIMP's premultiplied composite as straight
                // alpha, so antialiased edges come out dark. Passing here means ImageIO fixed it.
                #expect(difference >= 2, "\(name) no longer has dark edges, compare it like the rest")
                continue
            }
            #expect(difference < tolerance[name, default: 2], "\(name): \(difference)")
        }
    }
}
