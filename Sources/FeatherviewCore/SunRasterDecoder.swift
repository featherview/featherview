import Foundation

/// Sun Raster (.ras): a 32-byte big-endian header, an optional colormap, then rows padded to 16 bits.
enum SunRasterDecoder {
    static let format = OwnFormat.raster(name: "Sun Raster", extensions: ["ras", "sun"],
                                         size: { data, _ in try size(data) },
                                         decode: { data, _ in try decode(data) })

    private struct Header {
        let width, height, depth, type, mapType, mapLength: Int
    }

    private static func header(_ reader: inout ByteReader) throws -> Header {
        guard reader.remaining >= 32, try reader.u32be() == 0x59A6_6A95 else { throw OwnDecodeError.notThisFormat }
        let width = try reader.u32be(), height = try reader.u32be(), depth = try reader.u32be()
        _ = try reader.u32be()  // length: 0 in old files, and we compute it anyway
        return Header(width: width, height: height, depth: depth,
                      type: try reader.u32be(), mapType: try reader.u32be(), mapLength: try reader.u32be())
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
        guard [1, 8, 24, 32].contains(h.depth), (0...3).contains(h.type), (0...2).contains(h.mapType)
        else { throw OwnDecodeError.unsupported }

        // Colormap: all reds, then all greens, then all blues. Type 2 ("raw") maps are skipped.
        let map = try reader.take(h.mapLength)
        var palette: [(UInt8, UInt8, UInt8)] = []
        if h.mapType == 1, h.mapLength > 0 {
            guard h.mapLength % 3 == 0 else { throw OwnDecodeError.corrupt }
            let n = h.mapLength / 3, m = map.startIndex
            palette = (0..<n).map { (map[m + $0], map[m + n + $0], map[m + 2 * n + $0]) }
        }

        let stride = (width * h.depth + 15) / 16 * 2
        let body = h.type == 2 ? try unpackRLE(&reader, count: stride * height) : Array(try reader.take(stride * height))
        let rgb = h.type == 3

        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let row = y * stride
            for x in 0..<width {
                let c: (UInt8, UInt8, UInt8)
                switch h.depth {
                case 1:
                    let bit = Int(body[row + x / 8] >> (7 - x % 8) & 1)
                    c = bit < palette.count ? palette[bit] : bit == 1 ? (0, 0, 0) : (255, 255, 255)
                case 8:
                    let i = body[row + x]
                    c = palette.isEmpty ? (i, i, i) : Int(i) < palette.count ? palette[Int(i)] : (0, 0, 0)
                default:
                    let p = row + x * h.depth / 8 + (h.depth == 32 ? 1 : 0)  // 32-bit skips the pad byte
                    c = rgb ? (body[p], body[p + 1], body[p + 2]) : (body[p + 2], body[p + 1], body[p])
                }
                image[x, y] = (c.0, c.1, c.2, 255)
            }
        }
        return image
    }

    /// Type 2: 0x80 is the escape; 0x80 0x00 is a literal 0x80, 0x80 n v is n + 1 copies of v.
    static func unpackRLE(_ reader: inout ByteReader, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(min(count, reader.remaining * 86))  // 3 input bytes expand to at most 256
        while out.count < count {
            let b = try reader.u8()
            guard b == 0x80 else { out.append(b); continue }
            let n = Int(try reader.u8())
            if n == 0 { out.append(0x80); continue }
            out.append(contentsOf: repeatElement(try reader.u8(), count: min(n + 1, count - out.count)))
        }
        return out
    }
}
