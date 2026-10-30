import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDCompositeTests {
    typealias RGB = (UInt8, UInt8, UInt8)

    /// Pseudo-random pixels; the first three of each row are equal, so RLE rows get repeat and literal runs.
    static func noise(width: Int, height: Int) -> [RGB] {
        var state: UInt32 = 2024
        func next() -> UInt8 { state = state &* 1_664_525 &+ 1_013_904_223; return UInt8(truncatingIfNeeded: state >> 24) }
        var pixels: [RGB] = []
        for _ in 0..<height {
            let first = (next(), next(), next())
            for x in 0..<width { pixels.append(x < 3 ? first : (next(), next(), next())) }
        }
        return pixels
    }

    static func write(_ data: Data, _ name: String = "a.psd") throws -> URL {
        let url = try Fixtures.makeTempDir().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// The decoded bytes as stored, without colour conversion.
    static func pixels(_ image: CGImage) -> [RGB] {
        let data = image.dataProvider!.data! as Data
        return (0..<image.height).flatMap { y in
            (0..<image.width).map { x in
                let i = y * image.bytesPerRow + x * 4
                return (data[i], data[i + 1], data[i + 2])
            }
        }
    }

    static func same(_ a: [RGB], _ b: [RGB]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    }

    @Test(arguments: [(1, 0), (1, 1), (2, 0), (2, 1)])  // (version, compression)
    func readsRawAndRLEInBothVersions(version: Int, compression: Int) throws {
        let pixels = Self.noise(width: 7, height: 5)
        let url = try Self.write(PSDFixture.make(width: 7, height: 5, pixels: pixels, version: version, compression: compression))
        let composite = try #require(PSDComposite(url: url))
        #expect(composite.width == 7 && composite.height == 5)
        let image = try composite.decode(size: PixelSize(width: 7, height: 5))
        #expect(image.width == 7 && image.height == 5)
        #expect(Self.same(Self.pixels(image), pixels))
    }

    /// 2048 × 600 into one row: each band (600 rows) spans two 1 MB reads (512 rows of 2048).
    @Test(arguments: [0, 1]) func bandsLargerThanOneReadAverageAllRows(compression: Int) throws {
        let (width, height) = (2048, 600)
        let pixels = Self.noise(width: width, height: height)
        let url = try Self.write(PSDFixture.make(width: width, height: height, pixels: pixels, compression: compression))
        let image = try #require(PSDComposite(url: url)).decode(size: PixelSize(width: 2, height: 1))
        let expected: [RGB] = (0..<2).map { half in
            var sums = (0, 0, 0)
            for y in 0..<height {
                for x in half * width / 2 ..< (half + 1) * width / 2 {
                    let p = pixels[y * width + x]
                    sums = (sums.0 + Int(p.0), sums.1 + Int(p.1), sums.2 + Int(p.2))
                }
            }
            let n = height * width / 2
            return (UInt8((sums.0 + n / 2) / n), UInt8((sums.1 + n / 2) / n), UInt8((sums.2 + n / 2) / n))
        }
        #expect(Self.same(Self.pixels(image), expected))
    }

    @Test func areaAveragesOnDownscale() throws {
        let pixels: [RGB] = [(0, 0, 0), (10, 20, 30), (100, 100, 100), (200, 0, 50),
                             (2, 2, 2), (12, 22, 32), (100, 100, 100), (0, 0, 52)]
        let url = try Self.write(PSDFixture.make(width: 4, height: 2, pixels: pixels))
        let image = try #require(PSDComposite(url: url)).decode(size: PixelSize(width: 2, height: 1))
        #expect(Self.same(Self.pixels(image), [(6, 11, 16), (100, 50, 76)]))
    }

    @Test(arguments: [0, 1]) func regionMatchesCropOfFullDecode(compression: Int) throws {
        let pixels = Self.noise(width: 9, height: 7)
        let composite = try #require(PSDComposite(url: try Self.write(PSDFixture.make(width: 9, height: 7, pixels: pixels, compression: compression))))
        let full = Self.pixels(try composite.decode(size: PixelSize(width: 9, height: 7)))
        let part = Self.pixels(try composite.decode(region: CGRect(x: 2, y: 3, width: 4, height: 3), size: PixelSize(width: 4, height: 3)))
        let crop = (3..<6).flatMap { y in (2..<6).map { full[y * 9 + $0] } }
        #expect(Self.same(part, crop))
    }

    @Test func regionAtImageEdge() throws {
        let pixels = Self.noise(width: 9, height: 7)
        let composite = try #require(PSDComposite(url: try Self.write(PSDFixture.make(width: 9, height: 7, pixels: pixels))))
        let image = try composite.decode(region: CGRect(x: 5, y: 4, width: 4, height: 3), size: PixelSize(width: 2, height: 2))
        func mean(_ xs: Range<Int>, _ ys: Range<Int>) -> RGB {
            var sum = (0, 0, 0)
            for y in ys { for x in xs { let p = pixels[y * 9 + x]; sum.0 += Int(p.0); sum.1 += Int(p.1); sum.2 += Int(p.2) } }
            let n = xs.count * ys.count
            return (UInt8((sum.0 + n / 2) / n), UInt8((sum.1 + n / 2) / n), UInt8((sum.2 + n / 2) / n))
        }
        let expected = [mean(5..<7, 4..<5), mean(7..<9, 4..<5), mean(5..<7, 5..<7), mean(7..<9, 5..<7)]
        #expect(Self.same(Self.pixels(image), expected))
    }

    @Test func takesTheICCProfile() throws {
        let icc = try #require(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
        let pixels = Self.noise(width: 3, height: 2)
        let composite = try #require(PSDComposite(url: try Self.write(PSDFixture.make(width: 3, height: 2, pixels: pixels, icc: icc))))
        #expect(composite.icc == icc)
        let image = try composite.decode(size: PixelSize(width: 3, height: 2))
        #expect(image.colorSpace?.copyICCData() as Data? == icc)

        let plain = try #require(PSDComposite(url: try Self.write(PSDFixture.make(width: 3, height: 2, pixels: pixels))))
        #expect(plain.icc == nil)
        #expect(try plain.decode(size: PixelSize(width: 3, height: 2)).colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func declinesWhatImageIOReads() throws {
        let pixels = Self.noise(width: 3, height: 2)
        func declines(_ data: Data) throws -> Bool { PSDComposite(url: try Self.write(data)) == nil }
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, depth: 16)))
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, mode: 4)))
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, mode: 1)))
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, channels: 4)))
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, compression: 2)))
        #expect(try declines(Data(PSDFixture.make(width: 3, height: 2, pixels: pixels).prefix(20))))
        var signature = PSDFixture.make(width: 3, height: 2, pixels: pixels)
        signature[3] = UInt8(ascii: "X")
        #expect(try declines(signature))
        #expect(try declines(PSDFixture.make(width: 3, height: 2, pixels: pixels, version: 3)))
    }

    /// Saved without Maximize Compatibility, the stored composite isn't the picture, so ImageIO gets the file.
    @Test func declinesWithoutRealMergedData() throws {
        let pixels = Self.noise(width: 3, height: 2)
        #expect(PSDComposite(url: try Self.write(PSDFixture.make(width: 3, height: 2, pixels: pixels, realMerged: false))) == nil)
        #expect(PSDComposite(url: try Self.write(PSDFixture.make(width: 3, height: 2, pixels: pixels, realMerged: true))) != nil)
    }

    @Test func corruptRLEThrows() throws {
        let pixels = Self.noise(width: 7, height: 5)
        let table = 26 + 4 + 4 + 4 + 2  // header, colour mode data, resources, layer and mask info, compression
        var longRun = PSDFixture.make(width: 7, height: 5, pixels: pixels, compression: 1)
        longRun[table + 3 * 5 * 2] = UInt8(bitPattern: -127)  // the first row's first run repeats 128 times
        let long = try #require(PSDComposite(url: try Self.write(longRun)))
        #expect(throws: OwnDecodeError.corrupt) { try long.decode(size: PixelSize(width: 7, height: 5)) }
    }

    @Test(arguments: [1, 2])  // version
    func declinesLengthsPastTheEnd(version: Int) throws {
        let pixels = Self.noise(width: 2, height: 2)
        func declines(_ data: Data) throws -> Bool { PSDComposite(url: try Self.write(data)) == nil }

        // Layer and mask length near Int.max (PSB) or past the end (PSD).
        var layers = PSDFixture.make(width: 2, height: 2, pixels: pixels, version: version)
        let lengthSize = version == 1 ? 4 : 8
        layers.replaceSubrange(34 ..< 34 + lengthSize, with: [0x7F] + [UInt8](repeating: 0xFF, count: lengthSize - 2) + [0xF0])
        #expect(try declines(layers))

        // A raw composite claiming 0xFFFFFFFF × 0xFFFFFFFF.
        var huge = PSDFixture.make(width: 2, height: 2, pixels: pixels, version: version)
        huge.replaceSubrange(14 ..< 22, with: [UInt8](repeating: 0xFF, count: 8))
        #expect(try declines(huge))

        // RLE rows ending past the end of the file.
        var pastEnd = PSDFixture.make(width: 2, height: 2, pixels: pixels, version: version, compression: 1)
        pastEnd[34 + lengthSize + 2] = 0xFF
        #expect(try declines(pastEnd))
    }

    @Test func truncatedRawThrows() throws {
        let data = PSDFixture.make(width: 7, height: 5, pixels: Self.noise(width: 7, height: 5))
        let url = try Self.write(data)
        let composite = try #require(PSDComposite(url: url))
        try data.prefix(data.count - 10).write(to: url)
        #expect(throws: OwnDecodeError.corrupt) { try composite.decode(size: PixelSize(width: 7, height: 5)) }
    }

    /// A raw region reads only its own columns of each row: with the last row's trailing columns cut off the
    /// file, a region left of them still decodes.
    @Test func rawRegionReadsOnlyItsColumns() throws {
        let pixels = Self.noise(width: 9, height: 7)
        let data = PSDFixture.make(width: 9, height: 7, pixels: pixels)
        let url = try Self.write(data)
        let composite = try #require(PSDComposite(url: url))
        try data.prefix(data.count - 4).write(to: url)
        let image = try composite.decode(region: CGRect(x: 2, y: 4, width: 3, height: 3), size: PixelSize(width: 3, height: 3))
        #expect(Self.same(Self.pixels(image), (4..<7).flatMap { y in (2..<5).map { pixels[y * 9 + $0] } }))
    }

    /// Full-width raw rows come in one read per channel band; narrower regions read row by row.
    @Test func rawFullWidthBandIsOneRead() throws {
        var reads: [[Int]] = []
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 27)
        defer { buffer.deallocate() }
        let read = { (offset: Int, count: Int, into: UnsafeMutablePointer<UInt8>) in reads.append([offset, count, into - buffer]) }
        PSDComposite.rawBand(channel: 1, rows: 3..<6, x0: 0, rw: 9, width: 9, height: 7, dataStart: 100, into: buffer, read: read)
        #expect(reads == [[100 + (7 + 3) * 9, 27, 0]])
        reads = []
        PSDComposite.rawBand(channel: 1, rows: 3..<5, x0: 2, rw: 3, width: 9, height: 7, dataStart: 100, into: buffer, read: read)
        #expect(reads == [[100 + 10 * 9 + 2, 3, 0], [100 + 11 * 9 + 2, 3, 3]])
    }

    /// PSB's limit, 300,000 per side, keeps a row of one output pixel's sum within 32 bits.
    @Test func sidesOverThePSBLimitAreRejected() throws {
        let pixels = [RGB](repeating: (255, 255, 255), count: 300_001)
        let over = try Self.write(PSDFixture.make(width: 300_001, height: 1, pixels: pixels, version: 2))
        #expect(PSDComposite(url: over) == nil)
        let at = try Self.write(PSDFixture.make(width: 300_000, height: 1, pixels: Array(pixels.dropLast()), version: 2))
        #expect(PSDComposite(url: at) != nil)
    }
}
