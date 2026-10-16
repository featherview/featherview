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

@Suite struct PageTests {
    @Test func multiPageTIFFHasPagesOthersHaveOne() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(ImageDecoder.pageCount(of: tiff) == 3)
        #expect(ImageDecoder.pageCount(of: jpeg) == 1)
        #expect(ImageDecoder.pageCount(of: dir.appendingPathComponent("missing.tif")) == 1)
    }

    /// By extension only, so a cached JPEG swaps in without the header read that `pageCount` needs.
    @Test func onlyTIFFNamesMayHavePages() {
        #expect(ImageFormats.mayHavePages(URL(fileURLWithPath: "/x/a.tif")))
        #expect(ImageFormats.mayHavePages(URL(fileURLWithPath: "/x/a.TIFF")))
        #expect(!ImageFormats.mayHavePages(URL(fileURLWithPath: "/x/a.jpg")))
        #expect(!ImageFormats.mayHavePages(URL(fileURLWithPath: "/x/a.gif")))
    }

    @Test func decodesEachPage() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        #expect(try ImageDecoder.decode(tiff, page: 2).width == 10)  // page n is 8 + n wide
        #expect(ImageDecoder.displaySize(of: tiff, page: 1)?.width == 9)
        #expect(throws: DecodeError.unreadable(tiff)) { try ImageDecoder.decode(tiff, page: 3) }
    }
    @Test func hdrImagesDecodeDeeperOnlyWhenAsked() throws {
        guard #available(macOS 15, *) else { return }
        let dir = try Fixtures.makeTempDir()
        let hdr = try Fixtures.writeHDRGainMap(to: dir.appendingPathComponent("gm.heic"))
        #expect(try ImageDecoder.decode(hdr, maxPixelSize: 64, halvingSteps: true, hdr: true).bitsPerComponent > 8)
        #expect(try ImageDecoder.decode(hdr, maxPixelSize: 64, halvingSteps: true).bitsPerComponent == 8)
    }

    @Test func sdrImagesStayEightBitWithTheHDRRequest() throws {
        let dir = try Fixtures.makeTempDir()
        let sdr = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 64, height: 48)
        #expect(try ImageDecoder.decode(sdr, maxPixelSize: 64, halvingSteps: true, hdr: true).bitsPerComponent == 8)
    }
}
