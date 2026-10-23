import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ClipboardImageTests {
    @Test func pngDataIsCompressedAndRoundTrips() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("c.jpg"), width: 200, height: 100)
        let image = try ImageDecoder.decode(url)
        let data = try #require(ClipboardImage.pngData(image))
        // NSImage's TIFF is uncompressed (w × h × 4) and the pasteboard refuses it above ~256 MB
        #expect(data.count < image.width * image.height * 4 / 2)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let back = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(back.width == 200 && back.height == 100)
    }

    /// A JPEG's orientation is applied: 4 × 2 turned is 2 × 4.
    @Test(arguments: [(UTType.png, 1, 8, 6, 8, 6), (.tiff, 1, 8, 6, 8, 6), (.jpeg, 6, 4, 2, 2, 4)])
    func pastedDataDecodes(type: UTType, orientation: Int, width: Int, height: Int, shownWidth: Int, shownHeight: Int) throws {
        let data = Fixtures.encoded(Fixtures.animationFrame(0, width: width, height: height), as: type, orientation: orientation)
        let image = try #require(ClipboardImage.image(from: data))
        #expect(image.width == shownWidth && image.height == shownHeight)
    }

    @Test func garbageAndEmptyAreNil() {
        #expect(ClipboardImage.image(from: Data()) == nil)
        #expect(ClipboardImage.image(from: Data("not an image".utf8)) == nil)
    }

    @Test func preferredTypeSkipsNonImages() {
        #expect(ClipboardImage.preferredType(["public.utf8-plain-text", "public.png"]) == "public.png")
        #expect(ClipboardImage.preferredType(["public.file-url"]) == nil)
        #expect(ClipboardImage.preferredType(["com.adobe.pdf", "public.tiff"]) == "public.tiff")
    }

    @Test func copiedFilesOpenTheFirstImageAndNeverTheirIcon() {
        let text = URL(fileURLWithPath: "/tmp/notes.txt"), photo = URL(fileURLWithPath: "/tmp/photo.jpg")
        // Finder's Copy puts the files' icon beside their URLs, as TIFF.
        let finder = ["public.file-url", "com.apple.icns", "public.tiff"]
        #expect(ClipboardImage.content(fileURLs: [text, photo], types: finder) == .file(photo))
        #expect(ClipboardImage.content(fileURLs: [text], types: finder) == nil)
        #expect(ClipboardImage.content(fileURLs: [], types: ["public.utf8-plain-text", "public.png"]) == .data(type: "public.png"))
        #expect(ClipboardImage.content(fileURLs: [], types: ["public.utf8-plain-text"]) == nil)
    }
}
