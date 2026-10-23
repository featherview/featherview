import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ThumbnailDecodeTests {
    private func centre(_ image: CGImage) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        try #require(RGBAImage(image))[image.width / 2, image.height / 2]
    }

    @Test func embeddedUsedWhenBigEnough() throws {
        let url = try Fixtures.writeJPEGWithForeignThumbnail(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"))
        let image = try ImageDecoder.thumbnail(url, side: 120, colorSpace: nil)
        #expect((image.width, image.height) == (120, 90))
        let pixel = try centre(image)
        #expect(pixel.b > 200 && pixel.r < 50)
    }

    @Test func decodesWhenEmbeddedTooSmall() throws {
        let url = try Fixtures.writeJPEGWithForeignThumbnail(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"))
        let image = try ImageDecoder.thumbnail(url, side: 400, colorSpace: nil)
        #expect((image.width, image.height) == (400, 300))
        let pixel = try centre(image)
        #expect(pixel.r > 200 && pixel.b < 50)
    }

    @Test func letterboxedEmbeddedIsSkipped() {
        func size(_ w: Int, _ h: Int) -> PixelSize { PixelSize(width: w, height: h) }
        #expect(!ImageDecoder.acceptsEmbedded(size(160, 120), image: size(6000, 4000), side: 100))
        #expect(ImageDecoder.acceptsEmbedded(size(160, 120), image: size(4000, 3000), side: 100))
        #expect(!ImageDecoder.acceptsEmbedded(size(160, 120), image: size(4000, 3000), side: 200))
        #expect(ImageDecoder.acceptsEmbedded(size(120, 160), image: size(3000, 4000), side: 100))
    }

    @Test func panoramaDecodeRoundedToWholePixelAccepted() {
        func size(_ w: Int, _ h: Int) -> PixelSize { PixelSize(width: w, height: h) }
        // ImageIO's own decodes at 128: the short side rounds to a whole pixel.
        #expect(ImageDecoder.acceptsEmbedded(size(128, 19), image: size(660, 100), side: 128))
        #expect(ImageDecoder.acceptsEmbedded(size(128, 16), image: size(780, 100), side: 128))
        #expect(ImageDecoder.acceptsEmbedded(size(128, 12), image: size(1040, 100), side: 128))
        #expect(ImageDecoder.acceptsEmbedded(size(20, 128), image: size(2000, 13200), side: 128))
        #expect(!ImageDecoder.acceptsEmbedded(size(128, 24), image: size(660, 100), side: 128))
    }

    @Test func smallImageNotEnlarged() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.png"),
                                          width: 50, height: 40, type: .png)
        let image = try ImageDecoder.thumbnail(url, side: 256, colorSpace: nil)
        #expect((image.width, image.height) == (50, 40))
    }

    @Test func orientationApplied() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"),
                                          width: 400, height: 300, orientation: 6)
        let image = try ImageDecoder.thumbnail(url, side: 200, colorSpace: nil)
        #expect((image.width, image.height) == (150, 200))
    }

    @Test func zeroByteAndCorruptThrow() throws {
        let dir = try Fixtures.makeTempDir()
        let corrupt = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        let empty = dir.appendingPathComponent("empty.jpg")
        try Data().write(to: empty)
        for url in [corrupt, empty] {
            #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.thumbnail(url, side: 128, colorSpace: nil) }
        }
    }

    @Test func animatedGIFShowsFirstFrame() throws {
        let url = try Fixtures.writeAnimatedGIF(to: Fixtures.makeTempDir().appendingPathComponent("a.gif"),
                                                delays: [0.1, 0.1, 0.1], width: 400, height: 300)
        let image = try ImageDecoder.thumbnail(url, side: 100, colorSpace: nil)
        let frame0 = try centre(Fixtures.animationFrame(0, width: 4, height: 4))
        let pixel = try centre(image)
        #expect(abs(Int(pixel.r) - Int(frame0.r)) < 10)
    }

    @Test func multiPageTIFFShowsPageOne() throws {
        let url = try Fixtures.writeMultiPageTIFF(to: Fixtures.makeTempDir().appendingPathComponent("a.tif"), pages: 3)
        #expect(try ImageDecoder.thumbnail(url, side: 256, colorSpace: nil).width == 8)
    }

    @Test func ownFormatThumbnail() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.qoi")
        try QOICodec.encode(RGBAImage(width: 400, height: 300)).write(to: url)
        let image = try ImageDecoder.thumbnail(url, side: 100, colorSpace: nil)
        #expect((image.width, image.height) == (100, 75))
    }

    @Test func deepImageComesBackEightBit() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.png"),
                                          width: 64, height: 48, type: .png, bitsPerComponent: 16)
        #expect(try ImageDecoder.thumbnail(url, side: 32, colorSpace: nil).bitsPerComponent == 8)
    }
}
