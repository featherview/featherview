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
        let labels = MetadataReader.fields(for: url).map(\.label)
        #expect(labels == ["Dimensions", "File size"])
        #expect(MetadataReader.fields(for: url).first?.value == "4 × 2")
    }

    @Test func registeringAgainReplacesTheFormat() {
        OwnDecoders.register(Self.toy)
        #expect(OwnDecoders.all.filter { $0.extensions.contains("fvtoy") }.count == 1)
    }

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

    @Test func builtInDecodersCoverTheSpec() {
        let extensions = Set(OwnDecoders.builtIn.flatMap(\.extensions))
        for ext in ["qoi", "pcx", "dcx", "xbm", "xpm", "wbmp", "ras", "iff", "lbm", "pdf", "pdn"] {
            #expect(extensions.contains(ext), "\(ext)")
        }
    }

    @Test func pixelCapIs256Megapixels() {
        #expect((try? checkedSize(16384, 16384)) != nil)
        #expect((try? checkedSize(65536, 4096)) != nil)
        #expect(throws: OwnDecodeError.corrupt) { try checkedSize(65536, 4097) }
    }
}
