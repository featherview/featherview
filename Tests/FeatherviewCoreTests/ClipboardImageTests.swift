import CoreGraphics
import Foundation
import ImageIO
import Testing
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
}
