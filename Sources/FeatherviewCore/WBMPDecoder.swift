import Foundation

/// Wireless bitmaps (WAP), type 0 only: uncompressed, one bit per pixel, MSB first, 1 = white.
enum WBMPDecoder {
    static let format = OwnFormat.raster(name: "WBMP", extensions: ["wbmp"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        return try header(&reader)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let (width, height) = try header(&reader)
        let rowBytes = (width + 7) / 8
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let row = try reader.take(rowBytes)
            for x in 0..<width where row[row.startIndex + x / 8] >> (7 - x % 8) & 1 == 1 {
                image[x, y] = (255, 255, 255, 255)
            }
        }
        return image
    }

    private static func header(_ reader: inout ByteReader) throws -> (width: Int, height: Int) {
        // Type 0 has no extension headers, so its fixed header byte is 0 too.
        guard try multiByte(&reader) == 0, try reader.u8() == 0 else { throw OwnDecodeError.notThisFormat }
        return try checkedSize(multiByte(&reader), multiByte(&reader))
    }

    /// 7 bits per byte, high bit set on all but the last byte.
    private static func multiByte(_ reader: inout ByteReader) throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let byte = try reader.u8()
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw OwnDecodeError.corrupt  // more than 28 bits: far beyond any size we accept
    }
}
