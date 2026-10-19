import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

struct QuickLookSupportTests {
    static func plist(_ path: String) throws -> [String: Any]? {
        let url = Fixtures.repo.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
    }

    /// A QOI of `width` × `height`, opaque red.
    static func qoi(_ dir: URL, _ name: String, width: Int, height: Int) throws -> URL {
        var image = RGBAImage(width: width, height: height)
        for i in stride(from: 0, to: image.pixels.count, by: 4) { image.pixels[i] = 255; image.pixels[i + 3] = 255 }
        let url = dir.appending(path: name)
        try QOICodec.encode(image).write(to: url)
        return url
    }

    @Test func contentTypesAreTheOwnFormats() throws {
        let info = try #require(try Self.plist("Resources/Info.plist"))
        let declarations = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        var typeOf = ["xbm": "public.xbitmap-image"]
        for declaration in declarations {
            let id = try #require(declaration["UTTypeIdentifier"] as? String)
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            for ext in tags?["public.filename-extension"] as? [String] ?? [] { typeOf[ext] = id }
        }
        var reached = Set<String>()
        for format in OwnDecoders.builtIn where format.name != "PDF" {
            for ext in format.extensions {
                let id = try #require(typeOf[ext], "\(format.name): .\(ext) has no type in Info.plist")
                #expect(QuickLookSupport.contentTypes.contains(id), "\(format.name): \(id) has no Finder preview")
                reached.insert(id)
            }
        }
        #expect(Set(QuickLookSupport.contentTypes) == reached)
        #expect(QuickLookSupport.contentTypes.count == Set(QuickLookSupport.contentTypes).count)
    }

    @Test func extensionPlistsListTheContentTypes() throws {
        let plists = try ["Resources/QuickLook/Thumbnail-Info.plist", "Resources/QuickLook/Preview-Info.plist"]
            .compactMap { try Self.plist($0) }
        #expect(!plists.isEmpty)
        for plist in plists {
            let attributes = (plist["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
            #expect(attributes?["QLSupportedContentTypes"] as? [String] == QuickLookSupport.contentTypes)
        }
    }

    @Test func thumbnailSizeFits() {
        let wide = QuickLookSupport.thumbnailSize(image: CGSize(width: 400, height: 267), maximum: CGSize(width: 256, height: 256))
        #expect(wide.width == 256 && abs(wide.height - 170.88) < 0.01)
        let tall = QuickLookSupport.thumbnailSize(image: CGSize(width: 267, height: 400), maximum: CGSize(width: 256, height: 256))
        #expect(tall.height == 256 && abs(tall.width - 170.88) < 0.01)
    }

    @Test func smallImageIsNotEnlarged() {
        #expect(QuickLookSupport.thumbnailSize(image: CGSize(width: 16, height: 16), maximum: CGSize(width: 256, height: 256))
            == CGSize(width: 16, height: 16))
    }

    @Test func thumbnailDecodesAQOI() throws {
        let url = try Self.qoi(try Fixtures.makeTempDir(), "a.qoi", width: 400, height: 300)
        let (image, size) = try QuickLookSupport.thumbnail(url, maximum: CGSize(width: 256, height: 256), scale: 2)
        #expect(image.width == 400 && image.height == 300)
        #expect(size == CGSize(width: 256, height: 192))
    }

    @Test func upperCaseExtensionDecodes() throws {
        let url = try Self.qoi(try Fixtures.makeTempDir(), "IMAGE.QOI", width: 40, height: 30)
        #expect(try QuickLookSupport.thumbnail(url, maximum: CGSize(width: 256, height: 256), scale: 1).image.width == 40)
    }

    @Test func multiPageShowsFirstPage() throws {
        let pages = try [(40, 30), (10, 10)].map { width, height in
            var image = RGBAImage(width: width, height: height)
            for i in stride(from: 3, to: image.pixels.count, by: 4) { image.pixels[i] = 255 }
            return try PCXCodec.encode(image)
        }
        func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        let header = 4 + 4 * (pages.count + 1)
        var bytes = le32(0x3ADE_68B1)
        var offset = header
        for page in pages { bytes += le32(offset); offset += page.count }
        bytes += le32(0)
        for page in pages { bytes += page }
        let url = try Fixtures.makeTempDir().appending(path: "two.dcx")
        try Data(bytes).write(to: url)
        let (_, size) = try QuickLookSupport.thumbnail(url, maximum: CGSize(width: 256, height: 256), scale: 1)
        #expect(size == CGSize(width: 40, height: 30))
        #expect(try QuickLookSupport.preview(url, screens: [PixelSize(width: 1000, height: 1000)]).width == 40)
    }

    @Test func corruptFileThrows() throws {
        let dir = try Fixtures.makeTempDir()
        let whole = try Data(contentsOf: try Self.qoi(dir, "a.qoi", width: 40, height: 30))
        let cut = dir.appending(path: "cut.qoi")
        try whole.prefix(20).write(to: cut)
        #expect(throws: (any Error).self) { try QuickLookSupport.thumbnail(cut, maximum: CGSize(width: 256, height: 256), scale: 2) }
        #expect(throws: (any Error).self) { try QuickLookSupport.preview(cut, screens: [PixelSize(width: 1000, height: 1000)]) }
    }

    @Test func previewFitsTheScreen() throws {
        let url = try Self.qoi(try Fixtures.makeTempDir(), "big.qoi", width: 4000, height: 3000)
        let image = try QuickLookSupport.preview(url, screens: [PixelSize(width: 1000, height: 1000)])
        #expect((1000...2000).contains(max(image.width, image.height)))
    }

    @Test func previewWithoutScreensStaysScreenSized() throws {
        let url = try Self.qoi(try Fixtures.makeTempDir(), "big.qoi", width: 8000, height: 6000)
        let image = try QuickLookSupport.preview(url, screens: [])
        #expect(max(image.width, image.height) <= 3024)
    }
}
