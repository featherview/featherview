import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct PSDRoutingTests {
    static func gradient(width: Int, height: Int) -> [(UInt8, UInt8, UInt8)] {
        (0..<height).flatMap { y in
            (0..<width).map { x in (UInt8(x * 255 / max(width - 1, 1)), UInt8(y * 255 / max(height - 1, 1)), UInt8((x + y) % 256)) }
        }
    }

    static func write(width: Int, height: Int, name: String = "a.psd", version: Int = 1, compression: Int = 0,
                      channels: Int = 3, depth: Int = 8) throws -> URL {
        let url = try Fixtures.makeTempDir().appendingPathComponent(name)
        try PSDFixture.make(width: width, height: height, pixels: gradient(width: width, height: height), version: version,
                            compression: compression, channels: channels, depth: depth).write(to: url)
        return url
    }

    @Test(arguments: [0, 1]) func fastPathMatchesImageIO(compression: Int) throws {
        let url = try Self.write(width: 64, height: 48, compression: compression)
        #expect(ImageDecoder.readsRegions(url))
        let ours = try #require(RGBAImage(try ImageDecoder.decode(url)))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let imageIO = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let theirs = try #require(RGBAImage(imageIO))
        #expect(ours.width == 64 && ours.height == 48 && theirs.width == 64 && theirs.height == 48)
        for y in 0..<48 {
            for x in 0..<64 {
                let a = ours[x, y], b = theirs[x, y]
                #expect(abs(Int(a.r) - Int(b.r)) <= 2 && abs(Int(a.g) - Int(b.g)) <= 2 && abs(Int(a.b) - Int(b.b)) <= 2,
                        "(\(x), \(y)): \(a) vs \(b)")
            }
        }
    }

    @Test func fitDecodeIsExactSize() throws {
        let url = try Self.write(width: 400, height: 200)
        let image = try ImageDecoder.decode(url, halvingSteps: true, fitting: [PixelSize(width: 100, height: 100)])
        #expect(image.width == 100 && image.height == 50)
    }

    @Test func thumbnailUsesTheReader() throws {
        let url = try Self.write(width: 400, height: 200)
        let image = try ImageDecoder.thumbnail(url, side: 64, colorSpace: nil)
        #expect(image.width == 64 && image.height == 32)
    }

    @Test(arguments: [(3, 16), (4, 8)])  // (channels, depth)
    func declinedPSDStillOpens(channels: Int, depth: Int) throws {
        let url = try Self.write(width: 20, height: 10, channels: channels, depth: depth)
        #expect(!ImageDecoder.readsRegions(url))
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 20 && image.height == 10)
    }

    @Test func readsRegionsOnlyForTheReader() throws {
        #expect(ImageDecoder.readsRegions(try Self.write(width: 8, height: 6, name: "a.PSB", version: 2)))
        #expect(ImageDecoder.readsRegions(try Self.write(width: 8, height: 6, compression: 1)))
        let jpeg = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 8, height: 6)
        #expect(!ImageDecoder.readsRegions(jpeg))
        #expect(!ImageDecoder.readsRegions(try Self.write(width: 8, height: 6, depth: 16)))
    }

    @Test func decodeRegionMatchesCrop() throws {
        let url = try Self.write(width: 64, height: 48)
        let region = CGRect(x: 8, y: 8, width: 32, height: 16)
        let image = try ImageDecoder.decodeRegion(url, region: region, step: 1, colorSpace: nil)
        #expect(image.width == 16 && image.height == 8)
        let crop = try #require(PSDComposite(url: url)).decode(region: region, size: PixelSize(width: 16, height: 8))
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(image), PSDCompositeTests.pixels(crop)))
    }
}
