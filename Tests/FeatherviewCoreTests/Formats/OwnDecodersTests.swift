import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct OwnDecodersTests {
    /// A toy format: byte 0 width, byte 1 height, byte 2 pages, then one grey byte per pixel.
    static let toy = OwnFormat.raster(
        name: "TOY", extensions: ["fvtoy"], hasPages: true,
        size: { data, _ in
            guard data.count >= 3 else { throw OwnDecodeError.truncated }
            return (Int(data[data.startIndex]), Int(data[data.startIndex + 1]))
        },
        pageCount: { data in data.count >= 3 ? Int(data[data.startIndex + 2]) : 1 },
        decode: { data, _ in
            var reader = ByteReader(data)
            let width = Int(try reader.u8()), height = Int(try reader.u8())
            try reader.skip(1)
            var image = RGBAImage(width: width, height: height)
            for y in 0..<height { for x in 0..<width { let v = try reader.u8(); image[x, y] = (v, v, v, 255) } }
            return image
        })

    init() { OwnDecoders.register(Self.toy) }

    func toyFile(width: UInt8, height: UInt8, pages: UInt8 = 1, truncate: Bool = false) throws -> URL {
        var bytes: [UInt8] = [width, height, pages] + [UInt8](repeating: 200, count: Int(width) * Int(height))
        if truncate { bytes.removeLast() }
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.FVTOY")  // extensions match without case
        try Data(bytes).write(to: url)
        return url
    }

    @Test func registeredFormatsAreListedAndDecodable() throws {
        let url = try toyFile(width: 4, height: 2)
        #expect(ImageFormats.isDecodable(url))
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 4, height: 2))
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 4 && image.height == 2)
        #expect(OwnDecoders.all.contains { $0.name == "TOY" })
    }

    @Test func pagesComeFromTheFormat() throws {
        let url = try toyFile(width: 2, height: 2, pages: 3)
        #expect(ImageFormats.mayHavePages(url))
        #expect(ImageDecoder.pageCount(of: url) == 3)
    }

    @Test func downsamplesLikeImageIO() throws {
        let url = try toyFile(width: 200, height: 100)
        let image = try ImageDecoder.decode(url, maxPixelSize: 50, halvingSteps: true)
        #expect(image.width == 50 && image.height == 25)
        let small = try ImageDecoder.decode(url, maxPixelSize: 500)  // never upscales
        #expect(small.width == 200)
    }

    @Test func truncatedFileThrowsUnreadable() throws {
        let url = try toyFile(width: 4, height: 2, truncate: true)
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
    }

    @Test func infoPanelShowsOwnFormatDimensions() throws {
        let url = try toyFile(width: 4, height: 2)
        let info = ImageInfo.read(url)
        #expect(info.picture.dimensions?.hasPrefix("4 × 2 · ") == true)
        #expect(info.formatLine.contains("4 × 2"))
        #expect(info.camera == nil && info.taken == nil && info.gps == nil && info.picture.profile == nil)
    }

    @Test func registeringAgainReplacesTheFormat() {
        OwnDecoders.register(Self.toy)
        #expect(OwnDecoders.all.filter { $0.extensions.contains("fvtoy") }.count == 1)
    }

    @Test func builtInDecodersCoverTheSpec() {
        let extensions = Set(OwnDecoders.builtIn.flatMap(\.extensions))
        for ext in ["qoi", "pcx", "dcx", "xbm", "xpm", "wbmp", "ras", "sun", "iff", "lbm", "ilbm", "pcd", "jxr", "wdp", "hdp",
                    "bpg", "pdf", "xcf", "psp", "pspimage", "pdn", "ff", "mac", "pntg", "pnt", "xwd", "fits", "fit", "fts",
                    "ani", "ora", "kra", "procreate"] {
            #expect(extensions.contains(ext), "\(ext)")
        }
    }

    @Test func pixelCapIs256Megapixels() {
        #expect((try? checkedSize(16384, 16384)) != nil)
        #expect((try? checkedSize(65536, 4096)) != nil)
        #expect(throws: OwnDecodeError.corrupt) { try checkedSize(65536, 4097) }
    }

    /// One small file per built-in format, so a format missing from `OwnDecoders.builtIn` fails here.
    struct BuiltInFile: Sendable, CustomTestStringConvertible {
        let name: String
        let width: Int, height: Int
        var pixel: (x: Int, y: Int, rgba: (UInt8, UInt8, UInt8, UInt8))? = nil
        let bytes: @Sendable () throws -> Data
        var testDescription: String { name }
    }

    static let builtInFiles: [BuiltInFile] = [
        BuiltInFile(name: "t.bpg", width: 16, height: 16) { Data(BPGDecoderTests.gradient) },
        BuiltInFile(name: "a.lbm", width: 3, height: 1, pixel: (1, 0, (255, 0, 0, 255))) {
            ILBMDecoderTests.form([ILBMDecoderTests.bmhd(width: 3, height: 1, planes: 2), ILBMDecoderTests.cmap(ILBMDecoderTests.fourColors),
                                   ILBMDecoderTests.chunk("BODY", ILBMDecoderTests.planar([[3, 1, 2]], planes: 2))])
        },
        BuiltInFile(name: "a.ras", width: 2, height: 1, pixel: (1, 0, (255, 255, 255, 255))) {
            SunRasterDecoderTests.ras(width: 2, height: 1, depth: 8, body: [0, 255])
        },
        BuiltInFile(name: "a.ani", width: 32, height: 32) {
            Data(ANIDecoderTests.ani(frames: [try ANIDecoderTests.ico(sizes: [32], colour: (0, 255, 0, 255))]))
        },
        BuiltInFile(name: "a.ff", width: 2, height: 1) { Data(FarbfeldDecoderTests.file) },
        BuiltInFile(name: "a.qoi", width: 17, height: 9) { QOICodec.encode(QOICodecTests.noise(width: 17, height: 9)) },
        BuiltInFile(name: "t.wbmp", width: 3, height: 2) { Data(WBMPDecoderTests.file) },
        BuiltInFile(name: "t.xpm", width: 3, height: 2) { Data(XPMDecoderTests.file.utf8) },
        BuiltInFile(name: "t.xbm", width: 3, height: 2) { Data(XBMDecoderTests.file.utf8) },
        BuiltInFile(name: "t.wdp", width: 2, height: 2) { JPEGXRDecoderTests.rgb },
        BuiltInFile(name: "img0001.pcd", width: 768, height: 512) { PhotoCDDecoderTests.file },
        BuiltInFile(name: "a.xwd", width: 1, height: 1) {
            Data(XWDDecoderTests.file(width: 1, height: 1, depth: 24, bitsPerPixel: 32, bytesPerLine: 4, visualClass: 4,
                                      masks: (0xFF0000, 0xFF00, 0xFF), pixels: [0, 1, 2, 3]))
        },
    ] + ["fits", "fit", "fts"].map { ext in
        BuiltInFile(name: "a.\(ext)", width: 3, height: 1) {
            Data(FITSDecoderTests.file([FITSDecoderTests.card("SIMPLE", "T"), FITSDecoderTests.card("BITPIX", "8"),
                                        FITSDecoderTests.card("NAXIS", "2"), FITSDecoderTests.card("NAXIS1", "3"),
                                        FITSDecoderTests.card("NAXIS2", "1")], data: [1, 2, 3]))
        }
    } + ["mac", "pntg", "pnt"].map { ext in
        BuiltInFile(name: "a.\(ext)", width: 576, height: 720) { Data(MacPaintDecoderTests.file()) }
    }

    @Test(arguments: builtInFiles) func builtInFormatDecodesThroughImageDecoder(_ file: BuiltInFile) throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent(file.name)
        try file.bytes().write(to: url)
        #expect(ImageFormats.isDecodable(url))
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: file.width, height: file.height))
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image.width == file.width && image.height == file.height)
        if let pixel = file.pixel { #expect(image[pixel.x, pixel.y] == pixel.rgba) }
    }
}

@Suite struct RGBAImageAndByteReaderTests {
    @Test func rgbaImageRoundTripsThroughCGImage() throws {
        var image = RGBAImage(width: 2, height: 1)
        image[0, 0] = (255, 0, 0, 255)
        image[1, 0] = (0, 0, 255, 128)
        let cg = try #require(image.makeCGImage())
        let back = try #require(RGBAImage(cg))
        #expect(back[0, 0] == (255, 0, 0, 255))
        let blue = back[1, 0]
        #expect(blue.b >= 254 && blue.a == 128 && blue.r == 0)
    }

    @Test func unpremultiplyRoundsAndSkipsOpaqueAndClearPixels() {
        var image = RGBAImage(width: 4, height: 1, pixels: [64, 32, 1, 128, 200, 100, 50, 255, 9, 9, 9, 0, 10, 20, 30, 20])
        image.unpremultiply()
        // (c * 255 + a / 2) / a, at most 255
        #expect(image.pixels == [128, 64, 2, 128, 200, 100, 50, 255, 9, 9, 9, 0, 128, 255, 255, 20])
    }

    @Test func byteReaderThrowsPastTheEnd() {
        var reader = ByteReader([1, 2, 3])
        #expect(throws: OwnDecodeError.truncated) { _ = try reader.u32be() }
    }

    @Test func byteReaderReadsTheDataWithoutCopyingIt() throws {
        // A header read must touch only the mapped pages it reads, so the reader can't copy the file.
        let count = 4096  // big enough that Data doesn't store it inline
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 7)
        var reader = ByteReader(Data(bytesNoCopy: buffer.baseAddress!, count: count, deallocator: .none))
        buffer[0] = 9
        #expect(try reader.u8() == 9)
        #expect(Array(try reader.take(2)) == [7, 7])
        #expect(reader.remaining == count - 3)
    }

    @Test func byteReaderReadsASliceFromItsStart() throws {
        var reader = ByteReader(Data([0, 1, 2, 3]).dropFirst(2))
        #expect(try reader.u16be() == 0x0203)
        #expect(reader.isAtEnd)
    }
}
