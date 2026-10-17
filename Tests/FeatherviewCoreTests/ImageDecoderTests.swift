import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
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

    @Test(arguments: [
        (3024, 4032, [(3024, 1964)], 2016),  // portrait on a landscape screen: the height limits it
        (4032, 3024, [(3024, 1964)], 4032),
        (8688, 5792, [(5120, 2880)], 4344),
        (5792, 8688, [(5120, 2880)], 4344),
        (40, 20, [(5120, 2880)], 40),        // never upscales
    ])
    func fitDecodeSizePerAxis(width: Int, height: Int, screens: [(Int, Int)], expected: Int) {
        let size = ImageDecoder.fitDecodeSize(image: PixelSize(width: width, height: height),
                                              screens: screens.map { PixelSize(width: $0.0, height: $0.1) })
        #expect(size == expected)
    }

    /// 4032 × 2016 / 4032 is exactly 2016; floating point can give 2016.0000001 and round up to full size.
    @Test func fitDecodeSizeExactBoundary() {
        #expect(ImageDecoder.fitDecodeSize(image: PixelSize(width: 3024, height: 4032),
                                           screens: [PixelSize(width: 3024, height: 2016)]) == 2016)
    }

    @Test func fitDecodeSizeTakesTheMostDemandingScreen() {
        let screens = [PixelSize(width: 3024, height: 1964), PixelSize(width: 5120, height: 2880)]
        #expect(ImageDecoder.fitDecodeSize(image: PixelSize(width: 3024, height: 4032), screens: screens) == 4032)
    }

    @Test func fitDecodeUsesDisplayedOrientation() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 4000, height: 2000, orientation: 6)
        let image = try ImageDecoder.decode(url, halvingSteps: true, fitting: [PixelSize(width: 3000, height: 1000)])
        #expect(image.width == 500)
        #expect(image.height == 1000)
    }

    @Test(arguments: [
        (8688, 0.25, 2),   // 2172 px: ¼, no full decode
        (8688, 0.5, 1),    // 4344 px: ½
        (8688, 0.3, 1),    // 2607 px is above ¼ (2172): ½
        (8688, 1.0, 0),
        (8688, 2.0, 0),    // enlarged on screen, never decoded above full
        (8688, 0.05, 3),   // JPEG's smallest step is ⅛
        (4033, 0.5, 1),    // 2016.5 rounds up to 2017, which ½ (2017) still covers
    ])
    func zoomStepIsTheSmallestHalvingStepThatCoversTheFactor(full: Int, factor: Double, expected: Int) {
        #expect(ImageDecoder.zoomStep(full: full, factor: factor) == expected)
    }

    @Test func decodesAtAHalvingStep() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("z.jpg"), width: 4000, height: 2000, orientation: 6)
        let image = try ImageDecoder.decode(url, halvingSteps: true, step: 2)
        #expect(image.width == 500)
        #expect(image.height == 1000)
    }

    /// Core Animation colour-converts an image on the main thread when it's first shown (≈18 ms for
    /// 12 MP); a display decode in the screen's colour space skips that.
    @Test func displayDecodeComesInTheScreensColorSpace() async throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("s.jpg"), width: 40, height: 20)
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = try ImageDecoder.decode(url, maxPixelSize: 40, halvingSteps: true, colorSpace: p3)
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        #expect(image.width == 40)
        let cache = ImageCache(capacity: 1, colorSpace: p3)
        #expect(try await cache.image(for: url, target: .fit([PixelSize(width: 40, height: 40)])).colorSpace?.name == CGColorSpace.displayP3)
        // Batch and Save As keep the file's colour space.
        #expect(try ImageDecoder.decode(url).colorSpace?.name == CGColorSpace.sRGB)
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

    @Test(arguments: [UTType.png, .tiff], [true, false])
    func deepSDRImagesDecodeAtEightBits(type: UTType, hdr: Bool) throws {
        let dir = try Fixtures.makeTempDir()
        let deep = try Fixtures.writeImage(to: dir.appendingPathComponent("deep.\(type.preferredFilenameExtension!)"),
                                           width: 64, height: 48, type: type, bitsPerComponent: 16)
        let image = try ImageDecoder.decode(deep, maxPixelSize: 64, halvingSteps: true, hdr: hdr)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
    }

    @Test func exrDecodesAsEightBitSDRWithoutTheHDRRequest() throws {
        let dir = try Fixtures.makeTempDir()
        let exr = try Fixtures.writeImage(to: dir.appendingPathComponent("a.exr"), width: 64, height: 48,
                                          type: UTType("com.ilm.openexr-image")!, bitsPerComponent: 16)
        let image = try ImageDecoder.decode(exr, maxPixelSize: 64, halvingSteps: true)
        #expect(image.bitsPerComponent == 8)
        #expect(image.colorSpace.map(CGColorSpaceUsesExtendedRange) == false)
    }

    @Test func exrKeepsItsRangeAtSixteenBitsWithTheHDRRequest() throws {
        guard #available(macOS 15, *) else { return }
        let dir = try Fixtures.makeTempDir()
        let exr = try Fixtures.writeImage(to: dir.appendingPathComponent("a.exr"), width: 64, height: 48,
                                          type: UTType("com.ilm.openexr-image")!, bitsPerComponent: 16)
        let image = try ImageDecoder.decode(exr, maxPixelSize: 64, halvingSteps: true, hdr: true)
        #expect(image.bitsPerComponent == 16)  // ImageIO gives 32-bit float: twice the spec's HDR memory
        #expect(image.bitsPerPixel == 64)
        #expect(image.colorSpace.map(CGColorSpaceUsesExtendedRange) == true)
    }

    @Test func floatTIFFsDecodeAtEightBitsWithTheHDRRequest() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeImage(to: dir.appendingPathComponent("f.tif"), width: 64, height: 48,
                                           type: .tiff, bitsPerComponent: 32)
        let image = try ImageDecoder.decode(tiff, maxPixelSize: 64, halvingSteps: true, hdr: true)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
    }

    @Test(arguments: [UTType.png, .tiff])
    func deepImagesKeepTheirDepthOutsideDisplayDecodes(type: UTType) throws {
        let dir = try Fixtures.makeTempDir()
        let deep = try Fixtures.writeImage(to: dir.appendingPathComponent("deep.\(type.preferredFilenameExtension!)"),
                                           width: 64, height: 48, type: type, bitsPerComponent: 16)
        #expect(try ImageDecoder.decode(deep, maxPixelSize: 32).bitsPerComponent == 16)  // batch and Save As
        #expect(try ImageDecoder.decode(deep).bitsPerComponent == 16)
    }
}
