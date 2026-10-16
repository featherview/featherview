import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PCXCodecTests {
    /// A 128-byte PCX header at the origin, RLE encoded.
    func header(bitsPerPixel: UInt8, planes: UInt8, width: Int, height: Int, bytesPerLine: Int,
                ega: [UInt8] = []) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 128)
        func put16(_ v: Int, _ i: Int) { h[i] = UInt8(v & 0xFF); h[i + 1] = UInt8(v >> 8) }
        h[0] = 0x0A; h[1] = 5; h[2] = 1; h[3] = bitsPerPixel
        put16(width - 1, 8); put16(height - 1, 10); put16(72, 12); put16(72, 14)
        h.replaceSubrange(16..<16 + ega.count, with: ega)
        h[65] = planes
        put16(bytesPerLine, 66)
        put16(1, 68)
        return h
    }

    func rgb(_ image: RGBAImage, _ x: Int, _ y: Int) -> [UInt8] {
        let p = image[x, y]
        return [p.r, p.g, p.b, p.a]
    }

    @Test func eightBitWithPalette() throws {
        let pixels: [UInt8] = header(bitsPerPixel: 8, planes: 1, width: 2, height: 2, bytesPerLine: 2)
            + [0xC2, 1, 2, 3]  // indices 1 1 / 2 3
        var palette = [UInt8](repeating: 0, count: 768)
        palette.replaceSubrange(3..<12, with: [10, 11, 12, 20, 21, 22, 30, 31, 32])
        let image = try PCXCodec.decode(Data(pixels + [0x0C] + palette))
        #expect(rgb(image, 0, 0) == [10, 11, 12, 255])
        #expect(rgb(image, 1, 0) == [10, 11, 12, 255])
        #expect(rgb(image, 0, 1) == [20, 21, 22, 255])
        #expect(rgb(image, 1, 1) == [30, 31, 32, 255])

        let grey = try PCXCodec.decode(Data(pixels))  // no palette: indices are grey levels
        #expect(rgb(grey, 1, 1) == [3, 3, 3, 255])
    }

    @Test func twentyFourBitWithRunsAcrossPlanes() throws {
        // Planes R [10 20 30 pad] G [0 0 5 pad] B [0 40 40 pad]; the 0-runs cross R→G and G→B.
        let data = header(bitsPerPixel: 8, planes: 3, width: 3, height: 1, bytesPerLine: 4)
            + [10, 20, 30, 0xC3, 0, 5, 0xC2, 0, 0xC2, 40, 0]
        let image = try PCXCodec.decode(Data(data))
        #expect(rgb(image, 0, 0) == [10, 0, 0, 255])
        #expect(rgb(image, 1, 0) == [20, 0, 40, 255])
        #expect(rgb(image, 2, 0) == [30, 5, 40, 255])
    }

    @Test func monochromeIgnoresPadding() throws {
        // 10 pixels wide in 4 bytes per line; padding bits are set and must not show.
        let data = header(bitsPerPixel: 1, planes: 1, width: 10, height: 2, bytesPerLine: 4)
            + [0xAA, 0xC1, 0xFF, 0xC2, 0x77]  // 1010101011 + padding
            + [0x00, 0x3F, 0xC2, 0x00]        // 0000000000 + padding
        let image = try PCXCodec.decode(Data(data))
        let size = try PCXCodec.size(Data(data))
        #expect(size.width == 10 && size.height == 2)
        #expect((0..<10).map { image[$0, 0].r } == [255, 0, 255, 0, 255, 0, 255, 0, 255, 255])
        #expect((0..<10).allSatisfy { image[$0, 1] == (0, 0, 0, 255) })
    }

    @Test func sixteenColoursFromFourPlanes() throws {
        let ega: [UInt8] = (0..<48).map { i -> UInt8 in UInt8(i / 3 * 16 + i % 3) }
        // Pixel 0 is index 5 (planes 0 and 2), pixel 1 is index 10 (planes 1 and 3).
        let data = header(bitsPerPixel: 1, planes: 4, width: 2, height: 1, bytesPerLine: 2, ega: ega)
            + [0x80, 0, 0x40, 0, 0x80, 0, 0x40, 0]
        let image = try PCXCodec.decode(Data(data))
        #expect(rgb(image, 0, 0) == [80, 81, 82, 255])
        #expect(rgb(image, 1, 0) == [160, 161, 162, 255])
    }

    @Test func versionThreeUsesTheDefaultEGAPalette() throws {
        // Version 3 has no palette in the header (it's zero): indices are the standard 16 EGA colours.
        var nibbles = header(bitsPerPixel: 4, planes: 1, width: 4, height: 1, bytesPerLine: 2)
        nibbles[1] = 3; nibbles[2] = 0
        nibbles += [0x16, 0xF9]  // indices 1, 6, 15, 9
        let image = try PCXCodec.decode(Data(nibbles))
        #expect(rgb(image, 0, 0) == [0, 0, 170, 255])
        #expect(rgb(image, 1, 0) == [170, 85, 0, 255])
        #expect(rgb(image, 2, 0) == [255, 255, 255, 255])
        #expect(rgb(image, 3, 0) == [85, 85, 255, 255])

        var planar = header(bitsPerPixel: 1, planes: 4, width: 1, height: 1, bytesPerLine: 2)
        planar[1] = 3; planar[2] = 0
        planar += [0x80, 0, 0, 0, 0x80, 0, 0, 0]  // index 5 (planes 0 and 2)
        #expect(rgb(try PCXCodec.decode(Data(planar)), 0, 0) == [170, 0, 170, 255])
    }

    @Test func thirtyTwoBitFromFourPlanes() throws {
        // Planes R [10 20] G [30 40] B [50 60] A [255 128]; 255 needs a run of one.
        let data = header(bitsPerPixel: 8, planes: 4, width: 2, height: 1, bytesPerLine: 2)
            + [10, 20, 30, 40, 50, 60, 0xC1, 255, 128]
        let image = try PCXCodec.decode(Data(data))
        #expect(rgb(image, 0, 0) == [10, 30, 50, 255])
        #expect(rgb(image, 1, 0) == [20, 40, 60, 128])
    }

    @Test func sixteenColoursFromNibblesUncompressed() throws {
        let ega: [UInt8] = (0..<48).map { i -> UInt8 in UInt8(i / 3 * 16 + i % 3) }
        var data = header(bitsPerPixel: 4, planes: 1, width: 3, height: 1, bytesPerLine: 2, ega: ega)
        data[2] = 0  // encoding 0: 0xF0 is a plain byte, not a run
        data += [0x5A, 0xF0]  // indices 5, 10, 15 (+ a padding nibble)
        let image = try PCXCodec.decode(Data(data))
        #expect(rgb(image, 0, 0) == [80, 81, 82, 255])
        #expect(rgb(image, 1, 0) == [160, 161, 162, 255])
        #expect(rgb(image, 2, 0) == [240, 241, 242, 255])
    }

    @Test func encoderWritesGoldenBytes() throws {
        var image = RGBAImage(width: 2, height: 1)
        image[0, 0] = (10, 20, 30, 255)
        image[1, 0] = (200, 200, 0, 128)  // alpha is dropped
        let expected = header(bitsPerPixel: 8, planes: 3, width: 2, height: 1, bytesPerLine: 2)
            + [10, 0xC1, 200,  20, 0xC1, 200,  30, 0]  // a literal ≥ 0xC0 needs a run of one
        #expect([UInt8](try PCXCodec.encode(image)) == expected)
    }

    @Test func roundTrip() throws {
        var image = RGBAImage(width: 13, height: 7)
        var seed: UInt32 = 12345
        for y in 0..<7 {
            for x in 0..<13 {
                var c = [UInt8]()
                for _ in 0..<3 { seed = seed &* 1_103_515_245 &+ 12345; c.append(UInt8(seed >> 24)) }
                if x % 4 == 0 { c = [c[0], c[0], 0xC5] }  // some runs and high bytes
                image[x, y] = (c[0], c[1], c[2], 255)
            }
        }
        #expect(try PCXCodec.decode(try PCXCodec.encode(image)) == image)
    }

    @Test func dcxPagesThroughImageDecoder() throws {
        OwnDecoders.register(PCXCodec.pcx)
        OwnDecoders.register(PCXCodec.dcx)
        let first = try PCXCodec.encode(RGBAImage(width: 3, height: 2))
        let second = try PCXCodec.encode(RGBAImage(width: 5, height: 4))
        func u32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(v >> ($0 * 8) & 0xFF) } }
        let table = u32(0x3ADE68B1) + u32(16) + u32(16 + first.count) + u32(0)
        let url = try Fixtures.makeTempDir().appendingPathComponent("pages.dcx")
        try Data(table + first + second).write(to: url)

        #expect(ImageDecoder.pageCount(of: url) == 2)
        #expect(ImageDecoder.displaySize(of: url, page: 1) == CGSize(width: 5, height: 4))
        let page = try ImageDecoder.decode(url, page: 1)
        #expect(page.width == 5 && page.height == 4)
        #expect(try ImageDecoder.decode(url).width == 3)
        #expect(throws: OwnDecodeError.corrupt) { try PCXCodec.dcxPage(Data(table + first + second), 2) }
    }

    @Test func badInputThrows() throws {
        let good = [UInt8](try PCXCodec.encode(RGBAImage(width: 4, height: 4)))
        #expect(throws: OwnDecodeError.truncated) { try PCXCodec.decode(Data(good.dropLast(3))) }
        #expect(throws: OwnDecodeError.truncated) { try PCXCodec.decode(Data(good.prefix(60))) }
        #expect(throws: OwnDecodeError.notThisFormat) { try PCXCodec.decode(Data([0x0B] + good.dropFirst())) }

        var flipped = good
        flipped[8] = 5; flipped[9] = 0; flipped[4] = 9  // xMax < xMin
        #expect(throws: OwnDecodeError.corrupt) { try PCXCodec.decode(Data(flipped)) }
        var narrow = good
        narrow[66] = 1  // fewer bytes per line than the width needs
        #expect(throws: OwnDecodeError.corrupt) { try PCXCodec.decode(Data(narrow)) }
        let cga = header(bitsPerPixel: 2, planes: 1, width: 4, height: 1, bytesPerLine: 2) + [0, 0]
        #expect(throws: OwnDecodeError.unsupported) { try PCXCodec.decode(Data(cga)) }
        #expect(PCXCodec.dcxPageCount(Data(good)) == 0)
    }

    @Test func bytesPerLineFarAboveTheWidthIsCorrupt() {
        // 1 pixel wide but 65535 bytes per line: would make the scanline buffer gigabytes for a tiny image
        let data = header(bitsPerPixel: 8, planes: 4, width: 1, height: 4096, bytesPerLine: 65535)
            + [UInt8](repeating: 0xFF, count: 64)
        #expect(throws: OwnDecodeError.corrupt) { try PCXCodec.decode(Data(data)) }
    }

    @Test func pixelBytesAreNotReadAsAPalette() throws {
        // Uncompressed 8-bit grey, no palette; the pixel byte 769 from the end happens to be 0x0C.
        var data = header(bitsPerPixel: 8, planes: 1, width: 30, height: 30, bytesPerLine: 30)
        data[2] = 0
        var pixels = (0..<900).map { UInt8($0 % 200 + 20) }
        pixels[900 - 769] = 0x0C
        data += pixels
        let image = try PCXCodec.decode(Data(data))
        #expect(rgb(image, 0, 0) == [20, 20, 20, 255])
    }

    @Test func dcxPageOffsetPastTheEndThrows() {
        // magic, one page at 4096 or 0xFFFFFFFF, both past the end of the file
        #expect(throws: OwnDecodeError.truncated) {
            try PCXCodec.dcxPage(Data([0xB1, 0x68, 0xDE, 0x3A, 0x00, 0x10, 0x00, 0x00, 0, 0, 0, 0]), 0)
        }
        #expect(throws: OwnDecodeError.truncated) {
            try PCXCodec.dcxPage(Data([0xB1, 0x68, 0xDE, 0x3A, 0xFF, 0xFF, 0xFF, 0xFF]), 0)
        }
    }

    @Test func encoderRejectsSidesTheHeaderCantHold() throws {
        // bytesPerLine is rounded up to even and must fit 16 bits; yMax = height - 1 must too
        #expect(throws: OwnDecodeError.unsupported) { try PCXCodec.encode(RGBAImage(width: 65535, height: 1)) }
        #expect(throws: OwnDecodeError.unsupported) { try PCXCodec.encode(RGBAImage(width: 1, height: 65537)) }
        #expect(try PCXCodec.decode(PCXCodec.encode(RGBAImage(width: 65534, height: 1))).width == 65534)
    }
}
