import Compression
import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

/// Builds `.procreate` files: a `Document.archive` written by NSKeyedArchiver under Procreate's class
/// names and keys, and the composite's tiles, bottom row first, premultiplied RGBA.
enum ProcreateFixture {
    @objc(ProcreateFixtureDocument) final class Document: NSObject, NSCoding {
        var size = "{5, 6}", tileSize = 4, orientation = 1, flippedHorizontally = false, flippedVertically = false
        var composite: Layer? = Layer()
        var icc: Data?
        /// Stored under `tileSize` instead of the number, to try a hostile archive.
        var oddTileSize: Any?
        override init() {}
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {
            coder.encode(size as NSString, forKey: "size")
            if let oddTileSize { coder.encode(oddTileSize, forKey: "tileSize") } else { coder.encode(tileSize, forKey: "tileSize") }
            coder.encode(orientation, forKey: "orientation")
            coder.encode(flippedHorizontally, forKey: "flippedHorizontally")
            coder.encode(flippedVertically, forKey: "flippedVertically")
            coder.encode(Layer(uuid: "11111111-2222"), forKey: "selectedLayer")
            coder.encode(composite, forKey: "composite")
            coder.encode(icc.map(Profile.init), forKey: "colorProfile")
        }
    }

    @objc(ProcreateFixtureLayer) final class Layer: NSObject, NSCoding {
        let uuid: String
        init(uuid: String = "C0FFEE00-0000-4000-8000-000000000001") { self.uuid = uuid }
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {
            coder.encode(uuid as NSString, forKey: "UUID")
            coder.encode(1.0 as Float, forKey: "opacity")
        }
    }

    @objc(ProcreateFixtureProfile) final class Profile: NSObject, NSCoding {
        let icc: Data
        init(_ icc: Data) { self.icc = icc }
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) { coder.encode(icc as NSData, forKey: "SiColorProfileArchiveICCDataKey") }
    }

    static func archive(_ document: Document) -> [UInt8] {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("SilicaDocument", for: Document.self)
        archiver.setClassName("SilicaLayer", for: Layer.self)
        archiver.setClassName("ValkyrieColorProfile", for: Profile.self)
        archiver.encode(document, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return Array(archiver.encodedData)
    }

    /// The 5×6 test picture, top row first, straight alpha: a gradient with one half-transparent pixel at (0, 0).
    /// Tile (1, 0) is left out of the file, so its pixels (x 4, y 2...5) are transparent.
    static func picture() -> RGBAImage {
        var image = RGBAImage(width: 5, height: 6)
        for y in 0..<6 { for x in 0..<5 { image[x, y] = (UInt8(x * 40), UInt8(y * 40), 100, 255) } }
        image[0, 0] = (100, 0, 0, 128)
        for y in 2..<6 { image[4, y] = (0, 0, 0, 0) }
        return image
    }

    static func lzo(_ bytes: [UInt8]) -> [UInt8] { [UInt8(17 + bytes.count)] + bytes + [0x11, 0, 0] }

    static func lz4(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 1024)
        let n = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_LZ4)
        return Array(out.prefix(n))
    }

    /// Tile (col, row) of `picture()`: rows count up from the canvas bottom, edge tiles are clipped.
    static func tile(_ col: Int, _ row: Int, tileSize: Int = 4) -> [UInt8] {
        let image = picture()
        var bytes: [UInt8] = []
        for line in 0..<min(tileSize, image.height - row * tileSize) {
            let y = image.height - 1 - (row * tileSize + line)
            for x in col * tileSize..<min(image.width, (col + 1) * tileSize) {
                let p = image[x, y], a = Int(p.a)
                bytes += [p.r, p.g, p.b].map { UInt8((Int($0) * a + 127) / 255) } + [p.a]
            }
        }
        return bytes
    }

    static func file(_ document: Document = Document(), preview: Bool = true,
                     tiles: [(String, [UInt8])]? = nil) throws -> URL {
        let uuid = document.composite?.uuid ?? "none"
        var entries: [(name: String, bytes: [UInt8])] = [("Document.archive", archive(document))]
        entries += (tiles ?? [("0~0.lz4", lz4(tile(0, 0))), ("0~1.chunk", lzo(tile(0, 1))), ("1~1.chunk", lzo(tile(1, 1)))])
            .map { ("\(uuid)/\($0.0)", $0.1) }
        if preview { entries.append(("QuickLook/Thumbnail.png", try ZipFixture.png())) }
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.procreate")
        try ZipFixture.archive(entries).write(to: url)
        return url
    }
}

@Suite struct ProcreateDecoderTests {
    @Test func decodesTheFullCompositeFromItsTiles() throws {
        let url = try ProcreateFixture.file()
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 5, height: 6))
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image == ProcreateFixture.picture())
    }

    /// Orientation 1...4 is none, 180°, 270° and 90° clockwise; flips apply to the canvas before turning it.
    @Test(arguments: [(1, false, false), (2, false, false), (3, false, false), (4, false, false),
                      (1, true, false), (1, false, true), (4, true, false)])
    func showsTheCanvasTheWayItWasTurned(orientation: Int, flipH: Bool, flipV: Bool) throws {
        let document = ProcreateFixture.Document()
        document.orientation = orientation
        document.flippedHorizontally = flipH
        document.flippedVertically = flipV
        let url = try ProcreateFixture.file(document)
        let canvas = ProcreateFixture.picture(), w = canvas.width, h = canvas.height
        let turned = orientation >= 3
        var expected = RGBAImage(width: turned ? h : w, height: turned ? w : h)
        for y in 0..<h {
            for x in 0..<w {
                let fx = flipH ? w - 1 - x : x, fy = flipV ? h - 1 - y : y
                let (ox, oy) = switch orientation {
                case 2: (w - 1 - fx, h - 1 - fy)
                case 3: (fy, w - 1 - fx)
                case 4: (h - 1 - fy, fx)
                default: (fx, fy)
                }
                expected[ox, oy] = canvas[x, y]
            }
        }
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: expected.width, height: expected.height))
        #expect(RGBAImage(try ImageDecoder.decode(url)) == expected)
    }

    @Test func keepsTheDocumentsColourProfile() throws {
        let document = ProcreateFixture.Document()
        let icc = try #require(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
        document.icc = icc
        let image = try ImageDecoder.decode(try ProcreateFixture.file(document))
        #expect(image.colorSpace?.copyICCData() as Data? == icc)
    }

    @Test func fallsBackToTheStoredPreview() throws {
        let noComposite = ProcreateFixture.Document()
        noComposite.composite = nil
        let badTile = [("0~0.lz4", [UInt8](repeating: 7, count: 20))]
        for url in [try ProcreateFixture.file(noComposite), try ProcreateFixture.file(tiles: [])] {
            #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 6, height: 4))
        }
        // A broken tile only shows when the tiles are read, so the size is still the canvas's.
        for url in [try ProcreateFixture.file(noComposite), try ProcreateFixture.file(tiles: badTile),
                    try ProcreateFixture.file(tiles: [])] {
            let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
            #expect(image.width == 6 && image[1, 1] == (255, 0, 0, 255))
        }
        #expect(throws: DecodeError.self) { try ImageDecoder.decode(try ProcreateFixture.file(noComposite, preview: false)) }
        // Values of the wrong type in the archive fail without crashing, like any corrupt file.
        for odd: Any in ["256" as NSString, [256] as NSArray, 1e300 as NSNumber, -256 as NSNumber] {
            let document = ProcreateFixture.Document()
            document.oddTileSize = odd
            #expect(RGBAImage(try ImageDecoder.decode(try ProcreateFixture.file(document)))?.width == 6)
        }
    }
}
