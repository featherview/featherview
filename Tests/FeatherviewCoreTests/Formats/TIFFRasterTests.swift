import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct TIFFRasterTests {
    typealias RGB = PSDCompositeTests.RGB

    static func noise(width: Int, height: Int) -> [RGB] { PSDCompositeTests.noise(width: width, height: height) }

    static func write(_ data: Data) throws -> URL { try PSDCompositeTests.write(data, "a.tif") }

    @Test(arguments: [(false, false, 1, 1), (true, false, 5, 1), (false, true, 5, 2), (true, true, 8, 2), (false, false, 32946, 1)])
    func readsStripsLikeImageIO(bigEndian: Bool, bigTIFF: Bool, compression: Int, predictor: Int) throws {
        let pixels = Self.noise(width: 37, height: 23)
        let url = try Self.write(TIFFFixture.make(width: 37, height: 23, pixels: pixels, bigEndian: bigEndian, bigTIFF: bigTIFF,
                                                  compression: compression, predictor: predictor, rowsPerStrip: 4))
        let raster = try #require(TIFFRaster(url: url))
        #expect(raster.width == 37 && raster.height == 23)
        let image = try raster.decode(size: PixelSize(width: 37, height: 23))
        #expect(image.width == 37 && image.height == 23)
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(image), pixels))
        // A part stops each strip's decode at its last column in the strip's last row used.
        let part = try raster.decode(region: CGRect(x: 5, y: 3, width: 20, height: 14), size: PixelSize(width: 20, height: 14))
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(part), (3..<17).flatMap { y in (5..<25).map { pixels[y * 37 + $0] } }))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let imageIO = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let theirs = try #require(RGBAImage(imageIO))
        for y in 0..<23 {
            for x in 0..<37 {
                let a = pixels[y * 37 + x], b = theirs[x, y]
                #expect(a.0 == b.r && a.1 == b.g && a.2 == b.b, "(\(x), \(y))")
            }
        }
    }

    @Test(arguments: [1, 5, 8]) func readsTiles(compression: Int) throws {
        let pixels = Self.noise(width: 37, height: 23)
        let url = try Self.write(TIFFFixture.make(width: 37, height: 23, pixels: pixels, compression: compression, tile: (16, 16)))
        let raster = try #require(TIFFRaster(url: url))
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(try raster.decode(size: PixelSize(width: 37, height: 23))), pixels))
        let part = try raster.decode(region: CGRect(x: 10, y: 5, width: 20, height: 15), size: PixelSize(width: 20, height: 15))
        let crop = (5..<20).flatMap { y in (10..<30).map { pixels[y * 37 + $0] } }
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(part), crop))
    }

    @Test func areaAveragesAcrossBlocks() throws {
        let (width, height) = (40, 30)
        let pixels = Self.noise(width: width, height: height)
        let raster = try #require(TIFFRaster(url: try Self.write(TIFFFixture.make(width: width, height: height, pixels: pixels,
                                                                                   compression: 5, rowsPerStrip: 2))))
        let (ow, oh) = (7, 4)
        let image = try raster.decode(size: PixelSize(width: ow, height: oh))
        func mean(_ xs: Range<Int>, _ ys: Range<Int>) -> RGB {
            var sum = (0, 0, 0)
            for y in ys { for x in xs { let p = pixels[y * width + x]; sum.0 += Int(p.0); sum.1 += Int(p.1); sum.2 += Int(p.2) } }
            let n = xs.count * ys.count
            return (UInt8((sum.0 + n / 2) / n), UInt8((sum.1 + n / 2) / n), UInt8((sum.2 + n / 2) / n))
        }
        let expected = (0..<oh).flatMap { oy in
            (0..<ow).map { ox in mean(ox * width / ow ..< (ox + 1) * width / ow, oy * height / oh ..< (oy + 1) * height / oh) }
        }
        #expect(PSDCompositeTests.same(PSDCompositeTests.pixels(image), expected))
    }

    @Test func lzwRoundTrip() throws {
        var state: UInt32 = 7
        var bytes: [UInt8] = []
        while bytes.count < 70_000 {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(truncatingIfNeeded: state >> 24)
            bytes += [UInt8](repeating: value, count: state >> 20 & 7 == 0 ? Int(state >> 8 & 31) : 1)
        }
        bytes = Array(bytes.prefix(70_000))
        let packed = TIFFFixture.lzw(bytes)
        var out = [UInt8](repeating: 0, count: bytes.count)
        try packed.withUnsafeBufferPointer { packed in
            try out.withUnsafeMutableBufferPointer { try TIFFRaster.lzw(packed, into: $0) }
        }
        #expect(out == bytes)
    }

    @Test func takesTheICCProfile() throws {
        let icc = try #require(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
        let pixels = Self.noise(width: 3, height: 2)
        let raster = try #require(TIFFRaster(url: try Self.write(TIFFFixture.make(width: 3, height: 2, pixels: pixels, icc: icc))))
        #expect(raster.icc == icc)
        #expect(try raster.decode(size: PixelSize(width: 3, height: 2)).colorSpace?.copyICCData() as Data? == icc)

        let plain = try #require(TIFFRaster(url: try Self.write(TIFFFixture.make(width: 3, height: 2, pixels: pixels))))
        #expect(plain.icc == nil)
        #expect(try plain.decode(size: PixelSize(width: 3, height: 2)).colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func declinesWhatImageIOReads() throws {
        let pixels = Self.noise(width: 3, height: 2)
        func declines(_ data: Data) throws -> Bool { TIFFRaster(url: try Self.write(data)) == nil }
        #expect(try !declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, bits: 16)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, samples: 4)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, photometric: 1)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, planar: 2)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, compression: 7)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, predictor: 3)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, orientation: 6)))
        #expect(try declines(TIFFFixture.make(width: 3, height: 2, pixels: pixels, pages: 2)))
        #expect(try declines(Data(TIFFFixture.make(width: 3, height: 2, pixels: pixels).prefix(30))))
        var magic = TIFFFixture.make(width: 3, height: 2, pixels: pixels)
        magic[2] = 41
        #expect(try declines(magic))
        // The one strip's offset pointed past the end.
        let data = TIFFFixture.make(width: 3, height: 2, pixels: pixels)
        var moved = data
        let offsetEntry = try #require(Self.entry(273, in: moved))
        moved.replaceSubrange(offsetEntry + 8 ..< offsetEntry + 12, with: [0xFF, 0xFF, 0, 0])
        #expect(try declines(moved))
    }

    /// The byte offset of tag `tag`'s entry in a little-endian classic TIFF's first IFD.
    static func entry(_ tag: Int, in data: Data) -> Int? {
        let bytes = [UInt8](data)
        func le(_ at: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(bytes[at + $1]) << ($1 * 8) } }
        let ifd = le(4, 4)
        return (0..<le(ifd, 2)).map { ifd + 2 + $0 * 12 }.first { le($0, 2) == tag }
    }

    @Test func corruptDataThrows() throws {
        let pixels = Self.noise(width: 37, height: 23)
        let size = PixelSize(width: 37, height: 23)

        // LZW: the first strip (at byte 8) is Clear (9 bits), then a first code set to 511, past the table.
        var lzw = TIFFFixture.make(width: 37, height: 23, pixels: pixels, compression: 5, rowsPerStrip: 4)
        lzw[9] = lzw[9] & 0x80 | 0x7F
        lzw[10] = 0xFF
        let badCode = try #require(TIFFRaster(url: try Self.write(lzw)))
        #expect(throws: OwnDecodeError.corrupt) { try badCode.decode(size: size) }

        // Deflate: the first strip's byte count cut to half.
        var deflate = TIFFFixture.make(width: 37, height: 23, pixels: pixels, compression: 8, rowsPerStrip: 23)
        let counts = try #require(Self.entry(279, in: deflate))
        let half = (Int(deflate[counts + 8]) | Int(deflate[counts + 9]) << 8) / 2
        deflate.replaceSubrange(counts + 8 ..< counts + 12, with: [UInt8(half & 0xFF), UInt8(half >> 8), 0, 0])
        let truncated = try #require(TIFFRaster(url: try Self.write(deflate)))
        #expect(throws: OwnDecodeError.corrupt) { try truncated.decode(size: size) }

        // The file shortened after the header was read.
        let data = TIFFFixture.make(width: 37, height: 23, pixels: pixels, rowsPerStrip: 4)
        let url = try Self.write(data)
        let raster = try #require(TIFFRaster(url: url))
        try data.prefix(20).write(to: url)
        #expect(throws: OwnDecodeError.corrupt) { try raster.decode(size: size) }
    }
}
