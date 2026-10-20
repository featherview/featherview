import Foundation

/// MacPaint: always 576×720, one bit per pixel (1 = black), 72 PackBits-packed bytes per row after a
/// 512-byte header (version, patterns). Files copied off old Macs may carry a 128-byte MacBinary header.
enum MacPaintDecoder {
    static let format = OwnFormat.raster(name: "MacPaint", extensions: ["mac", "pntg", "pnt"],
                                         size: { data, _ in try start(data); return (576, 720) },
                                         decode: { data, _ in try decode(data) })

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        reader.offset = try start(data) + 512
        let bits = try ILBMDecoder.unpackByteRun1(&reader, count: 72 * 720)
        var image = RGBAImage(width: 576, height: 720, pixels: [UInt8](repeating: 255, count: 576 * 720 * 4))
        for y in 0..<720 {
            for x in 0..<576 where bits[y * 72 + x / 8] >> (7 - x % 8) & 1 == 1 { image[x, y] = (0, 0, 0, 255) }
        }
        return image
    }

    /// Where the MacPaint header starts: after a MacBinary header (file type "PNTG" at 65), else at 0.
    @discardableResult
    private static func start(_ data: Data) throws -> Int {
        guard data.count >= 512 else { throw OwnDecodeError.truncated }
        let bytes = [UInt8](data.prefix(132))
        let start = bytes[0] == 0 && bytes[65..<69].elementsEqual("PNTG".utf8) ? 128 : 0
        guard data.count >= start + 512 else { throw OwnDecodeError.truncated }
        var reader = ByteReader(data)
        reader.offset = start
        // No magic number: the version (0, 2 or 3) is all there is to check.
        guard [0, 2, 3].contains(try reader.u32be()) else { throw OwnDecodeError.notThisFormat }
        return start
    }
}
