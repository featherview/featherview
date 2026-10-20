import Compression
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

/// Builds zip archives byte by byte (PKWARE APPNOTE 4.3): local headers, central directory, end record.
enum ZipFixture {
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }

    static func deflate(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 64)
        let n = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        return Array(out.prefix(n))
    }

    /// `deflated` entries are compressed, the others stored.
    static func archive(_ entries: [(name: String, bytes: [UInt8])], deflated: Set<String> = []) -> Data {
        var body: [UInt8] = [], central: [UInt8] = []
        for (name, bytes) in entries {
            let method = deflated.contains(name) ? 8 : 0
            let payload = method == 8 ? deflate(bytes) : bytes
            let nameBytes = Array(name.utf8)
            let offset = body.count
            let common = le16(20) + le16(0) + le16(method) + le32(0) + le32(0)  // version, flags, method, time+date, crc
                + le32(payload.count) + le32(bytes.count) + le16(nameBytes.count) + le16(0)
            body += le32(0x0403_4B50) + common + nameBytes + payload
            central += le32(0x0201_4B50) + le16(20) + common + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameBytes
        }
        let end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
            + le32(central.count) + le32(body.count) + le16(0)
        return Data(body + central + end)
    }

    /// A 6×4 PNG, red with its top-left pixel transparent.
    static func png() throws -> [UInt8] {
        var image = RGBAImage(width: 6, height: 4)
        for y in 0..<4 { for x in 0..<6 { image[x, y] = (255, 0, 0, 255) } }
        image[0, 0] = (0, 0, 0, 0)
        let url = try Fixtures.makeTempDir().appendingPathComponent("m.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(image.makeCGImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        return Array(try Data(contentsOf: url))
    }
}

@Suite struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        let text = Array(String(repeating: "feather ", count: 50).utf8)
        let zip = try ZipArchive(ZipFixture.archive([("mimetype", Array("image/openraster".utf8)), ("a/b.txt", text)],
                                                    deflated: ["a/b.txt"]))
        #expect(try zip.read("mimetype") == Data("image/openraster".utf8))
        #expect(try zip.read("a/b.txt") == Data(text))
        #expect(try zip.read("missing") == nil)
    }

    @Test func rejectsBadArchives() throws {
        #expect(throws: OwnDecodeError.notThisFormat) { try ZipArchive(Data("not a zip at all, not even close".utf8)) }
        let good = ZipFixture.archive([("x", [1, 2, 3])])
        #expect(throws: OwnDecodeError.self) { try ZipArchive(good.dropFirst(20)).read("x") }
        // An entry claiming 4 GiB unpacked with 3 bytes of data fails before allocating.
        var huge = [UInt8](good)
        let central = huge.count - 22 - 47
        huge.replaceSubrange(central + 24..<central + 28, with: ZipFixture.le32(0xFFFF_FFFE))
        #expect(throws: OwnDecodeError.self) { try ZipArchive(Data(huge)).read("x") }
    }

    @Test(arguments: [("ora", "mergedimage.png"), ("kra", "mergedimage.png"), ("procreate", "QuickLook/Thumbnail.png")])
    func appFormatsShowTheirStoredImage(ext: String, entry: String) throws {
        let png = try ZipFixture.png()
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.\(ext)")
        try ZipFixture.archive([("mimetype", Array("x".utf8)), ("stack.xml", []), (entry, png)], deflated: [entry]).write(to: url)
        #expect(ImageFormats.isDecodable(url))
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 6, height: 4))
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image[1, 1] == (255, 0, 0, 255) && image[0, 0].a == 0)
        #expect(try ImageDecoder.decode(url, maxPixelSize: 3).width == 3)
    }

    @Test func archiveWithoutTheImageCantOpen() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.ora")
        try ZipFixture.archive([("stack.xml", [])]).write(to: url)
        #expect(throws: DecodeError.self) { try ImageDecoder.decode(url) }
    }
}
