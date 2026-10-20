import Foundation

/// farbfeld (suckless): "farbfeld", big-endian width and height, then 16-bit big-endian RGBA, straight alpha.
enum FarbfeldDecoder {
    static let format = OwnFormat.raster(name: "farbfeld", extensions: ["ff"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        return try header(&reader)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let (width, height) = try header(&reader)
        guard reader.remaining >= width * height * 8 else { throw OwnDecodeError.truncated }  // before allocating
        var image = RGBAImage(width: width, height: height)
        let src = try reader.take(width * height * 8)
        image.pixels.withUnsafeMutableBufferPointer { out in
            for i in 0..<width * height * 4 {
                let v = Int(src[src.startIndex + i * 2]) << 8 | Int(src[src.startIndex + i * 2 + 1])
                out[i] = UInt8((v * 255 + 32767) / 65535)
            }
        }
        return image
    }

    private static func header(_ reader: inout ByteReader) throws -> (width: Int, height: Int) {
        guard try reader.take(8).elementsEqual("farbfeld".utf8) else { throw OwnDecodeError.notThisFormat }
        return try checkedSize(reader.u32be(), reader.u32be())
    }
}
