import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ClipboardImageTests {
    @Test func pngDataIsCompressedAndRoundTrips() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("c.jpg"), width: 2000, height: 1000)
        let image = try ImageDecoder.decode(url)
        let data = try #require(ClipboardImage.pngData(image))
        // NSImage's TIFF is uncompressed (w × h × 4) and the pasteboard refuses it above ~256 MB
        #expect(data.count < image.width * image.height * 4 / 2)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let back = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(back.width == 2000 && back.height == 1000)
    }

    private func encoded(_ image: CGImage, as type: UTType, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    @Test func pngDataDecodes() throws {
        let data = try encoded(Fixtures.animationFrame(0, width: 8, height: 6), as: .png)
        let image = try #require(ClipboardImage.image(from: data))
        #expect(image.width == 8 && image.height == 6)
    }

    @Test func tiffDataDecodes() throws {
        let data = try encoded(Fixtures.animationFrame(0, width: 8, height: 6), as: .tiff)
        let image = try #require(ClipboardImage.image(from: data))
        #expect(image.width == 8 && image.height == 6)
    }

    @Test func jpegOrientationApplied() throws {
        let data = try encoded(Fixtures.animationFrame(0, width: 4, height: 2), as: .jpeg, orientation: 6)
        let image = try #require(ClipboardImage.image(from: data))
        #expect(image.width == 2 && image.height == 4)
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
