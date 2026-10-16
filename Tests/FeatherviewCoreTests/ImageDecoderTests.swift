import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageDecoderTests {
    @Test func appliesExifOrientation() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 40, height: 20, orientation: 6)
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 20, height: 40))
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 20)
        #expect(image.height == 40)
    }

    @Test func downsamplesLargeImages() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("big.png"), width: 4000, height: 2000, type: .png)
        let image = try ImageDecoder.decode(url, maxPixelSize: 500)
        #expect(max(image.width, image.height) == 500)
    }

    @Test func neverUpscales() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("s.jpg"), width: 40, height: 20)
        #expect(try ImageDecoder.decode(url, maxPixelSize: 4000).width == 40)
    }

    @Test func corruptFileThrows() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
        #expect(ImageDecoder.displaySize(of: dir.appendingPathComponent("missing.jpg")) == nil)
    }
}
