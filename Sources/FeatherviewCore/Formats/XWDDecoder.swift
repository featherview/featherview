import Foundation

/// X Window Dump (xwd, version 7): 25 big-endian header fields, the window name, a colormap of
/// 12-byte entries, then Z pixmap rows. Colormapped visuals look pixels up in the colormap, true
/// and direct colour ones read them through the red, green and blue masks.
enum XWDDecoder {
    static let format = OwnFormat.raster(name: "XWD", extensions: ["xwd"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    private struct Header {
        let headerSize, depth, width, height, byteOrder, bitOrder, bitsPerPixel, bytesPerLine, visualClass: Int
        let masks: [Int]
        let colors: Int
    }

    private static func header(_ reader: inout ByteReader) throws -> Header {
        guard reader.remaining >= 100 else { throw OwnDecodeError.truncated }
        var f: [Int] = []
        for _ in 0..<25 { f.append(try reader.u32be()) }
        guard f[1] == 7, f[0] >= 100 else { throw OwnDecodeError.notThisFormat }
        guard f[2] == 2 else { throw OwnDecodeError.unsupported }  // XY bitmaps and pixmaps: plane by plane, rare
        return Header(headerSize: f[0], depth: f[3], width: f[4], height: f[5], byteOrder: f[7], bitOrder: f[9],
                      bitsPerPixel: f[11], bytesPerLine: f[12], visualClass: f[13], masks: [f[14], f[15], f[16]],
                      colors: f[19])
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        let h = try header(&reader)
        let (width, height) = try checkedSize(h.width, h.height)
        return (width, height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let h = try header(&reader)
        let (width, height) = try checkedSize(h.width, h.height)
        let bpp = h.bitsPerPixel
        guard [1, 4, 8, 16, 24, 32].contains(bpp), h.bytesPerLine >= (width * bpp + 7) / 8 else { throw OwnDecodeError.unsupported }
        try reader.skip(h.headerSize - 100)

        var map: [Int: (UInt8, UInt8, UInt8)] = [:]
        for _ in 0..<h.colors {
            let pixel = try reader.u32be()
            let r = try reader.u16be(), g = try reader.u16be(), b = try reader.u16be()
            try reader.skip(2)
            map[pixel] = (UInt8(r >> 8), UInt8(g >> 8), UInt8(b >> 8))
        }
        // StaticGray, GrayScale, StaticColor, PseudoColor use the colormap; TrueColor, DirectColor the masks.
        let colormapped = h.visualClass < 4 || h.masks.allSatisfy { $0 == 0 }
        guard reader.remaining >= h.bytesPerLine * height else { throw OwnDecodeError.truncated }  // before allocating
        let rows = try reader.take(h.bytesPerLine * height)

        let channels = h.masks.map { mask -> (shift: Int, max: Int) in
            guard mask != 0 else { return (0, 1) }
            let shift = mask.trailingZeroBitCount
            return (shift, mask >> shift)
        }
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let row = rows.startIndex + y * h.bytesPerLine
            for x in 0..<width {
                let pixel: Int
                if bpp < 8 {
                    let bit = x * bpp, byte = Int(rows[row + bit / 8])
                    let shift = h.bitOrder == 1 ? 8 - bpp - bit % 8 : bit % 8
                    pixel = byte >> shift & (1 << bpp - 1)
                } else {
                    let start = row + x * bpp / 8, count = bpp / 8
                    var value = 0
                    for i in 0..<count { value = value << 8 | Int(rows[start + (h.byteOrder == 1 ? i : count - 1 - i)]) }
                    pixel = value
                }
                if colormapped {
                    let grey = UInt8(truncatingIfNeeded: pixel * 255 / max(1, 1 << min(h.depth, 8) - 1))
                    let c = map[pixel] ?? (grey, grey, grey)
                    image[x, y] = (c.0, c.1, c.2, 255)
                } else {
                    let c = channels.map { UInt8((pixel >> $0.shift & $0.max) * 255 / $0.max) }
                    image[x, y] = (c[0], c[1], c[2], 255)
                }
            }
        }
        return image
    }
}
