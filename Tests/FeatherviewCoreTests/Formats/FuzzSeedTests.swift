import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

/// One small valid file per own format, from the builders the decoder tests use: the fuzz seeds
/// (`FEATHERVIEW_FUZZ_SEEDS=<dir>` writes them for `scripts/fuzz.sh`) and the inputs of the prefix test.
@Suite struct FuzzSeedTests {
    static func seeds() throws -> [String: Data] {
        func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
        let pcx = try PCXCodec.encode(RGBAImage(width: 3, height: 2)), page2 = try PCXCodec.encode(RGBAImage(width: 5, height: 4))
        let dcxTable = Fixtures.le32(0x3ADE68B1) + Fixtures.le32(16) + Fixtures.le32(16 + pcx.count) + Fixtures.le32(0)
        var xcf = XCFBuilder(width: 3, height: 2)
        xcf.layers = [.init(width: 3, height: 2, type: 0, pixels: [255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3, 4, 5, 6, 7, 8, 9])]
        let png = try ZipFixture.png()
        let zipped = ZipFixture.archive([("mimetype", Array("x".utf8)), ("stack.xml", []), ("mergedimage.png", png)],
                                        deflated: ["mergedimage.png"])
        let fits = FITSDecoderTests.file([FITSDecoderTests.card("SIMPLE", "T"), FITSDecoderTests.card("BITPIX", "8"),
                                          FITSDecoderTests.card("NAXIS", "2"), FITSDecoderTests.card("NAXIS1", "2"),
                                          FITSDecoderTests.card("NAXIS2", "2")], data: [10, 20, 200, 250])
        let xwd = XWDDecoderTests.file(width: 2, height: 1, depth: 24, bitsPerPixel: 32, bytesPerLine: 8, visualClass: 4,
                                       masks: (0xFF0000, 0x00FF00, 0x0000FF), pixels: [0, 255, 0, 0, 0, 0, 0, 255])
        let ilbm = ILBMDecoderTests.form([ILBMDecoderTests.bmhd(width: 3, height: 1, planes: 2),
                                          ILBMDecoderTests.cmap(ILBMDecoderTests.fourColors),
                                          ILBMDecoderTests.chunk("BODY", ILBMDecoderTests.planar([[3, 1, 2]], planes: 2))])
        let ani = ANIDecoderTests.ani(frames: [try ANIDecoderTests.ico(sizes: [16, 32], colour: (255, 0, 0, 255)),
                                               try ANIDecoderTests.ico(sizes: [16], colour: (0, 0, 255, 255))])
        let pdf = try Fixtures.writePDF(to: Fixtures.makeTempDir().appendingPathComponent("doc.pdf"),
                                        pages: [CGSize(width: 20, height: 10), CGSize(width: 10, height: 20)], fill: 0.5)
        return [
            "QOI": Data(QOICodecTests.tinyBytes),
            "PCX": pcx,
            "DCX": Data(dcxTable) + pcx + page2,
            "XBM": Data(XBMDecoderTests.file.utf8),
            "XPM": Data(XPMDecoderTests.file.utf8),
            "WBMP": Data(WBMPDecoderTests.file),
            "Sun Raster": SunRasterDecoderTests.ras(width: 2, height: 1, depth: 8, map: [10, 20, 30, 40, 50, 60], body: [1, 0]),
            "IFF ILBM": ilbm,
            "GIMP XCF": xcf.data,
            "PaintShop Pro": Data(PSPDecoderTests.smallTwoLayerFile()),
            "Paint.NET": PDNDecoderTests.builder([.init(pixels: PDNDecoderTests.red)]).data,
            "farbfeld": Data(FarbfeldDecoderTests.file),
            "MacPaint": Data(MacPaintDecoderTests.file()),
            "XWD": Data(xwd),
            "FITS": Data(fits),
            "ANI": Data(ani),
            "OpenRaster": zipped,
            "Krita": zipped,
            "Procreate": try read(ProcreateFixture.file()),
            "Photo CD": PhotoCDDecoderTests.file,
            "JPEG XR": try #require(JPEGXRDecoderTests.rgb),
            "BPG": Data(BPGDecoderTests.gradient),
            "PDF": try read(pdf),
        ]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FEATHERVIEW_FUZZ_SEEDS"]?.isEmpty == false))
    func writesOneSeedPerOwnFormat() throws {
        let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["FEATHERVIEW_FUZZ_SEEDS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seeds = try Self.seeds()
        for format in OwnDecoders.builtIn {
            let data = try #require(seeds[format.name], "no seed for \(format.name)")
            _ = try format.decode(data, 0, nil)
            let url = dir.appendingPathComponent("\(format.name.lowercased()).\(format.extensions[0])")
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// Every prefix of a valid file (byte by byte up to 512, then every 64th) throws or decodes, never traps.
    @Test func everyPrefixOfASeedThrowsOrDecodes() throws {
        let seeds = try Self.seeds()
        for format in OwnDecoders.builtIn {
            let data = try #require(seeds[format.name], "no seed for \(format.name)")
            for n in Array(0..<min(512, data.count)) + Array(stride(from: 512, to: data.count, by: 64)) {
                let prefix = data.prefix(n)
                _ = format.size(prefix, 0)
                _ = format.pageCount(prefix)
                _ = try? format.decode(prefix, 0, nil)
            }
        }
    }
}
