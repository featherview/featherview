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
        let image = try ImageDecoder.decode(url, maxPixelSize: 600)
        #expect(max(image.width, image.height) == 600)
    }

    @Test func downsamplesForDisplayByHalvingSteps() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("big.jpg"), width: 4000, height: 2000)
        let image = try ImageDecoder.decode(url, maxPixelSize: 600, halvingSteps: true)
        #expect(max(image.width, image.height) == 1000)
    }

    @Test(arguments: [
        (4032, 3456, 4032),  // a 12 MP photo on a 3456 px screen: full size, no slow resample
        (4032, 2016, 2016),
        (4032, 2000, 2016),
        (4000, 600, 1000),
        (4000, 100, 500),    // JPEG's smallest step is ⅛
        (3001, 1500, 1501),  // odd sizes round up, as JPEG's scaled decode does
        (40, 4000, 40),
    ])
    func decodeSizeIsSmallestHalvingStepAtOrAboveTarget(full: Int, target: Int, expected: Int) {
        #expect(ImageDecoder.decodeSize(full: full, target: target) == expected)
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
