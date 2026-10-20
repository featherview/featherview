import Foundation

/// Kodak Photo CD (.pcd): 2048-byte sectors, "PCD_IPI" at 0x800, rotation in the low two bits of 0xE02,
/// the Base image (768×512) uncompressed at 0x30000. Each pair of rows is stored as two luma rows,
/// then one row each of half-width C1 and C2 (PhotoYCC, 4:2:0).
// shortcut: Base resolution only (768×512); 4Base/16Base need Huffman-coded residuals, add them if
// people view Photo CD scans at full size.
enum PhotoCDDecoder {
    static let format = OwnFormat.raster(name: "Photo CD", extensions: ["pcd"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static let width = 768, height = 512
    private static let baseOffset = 0x30000

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        try rotation(data) % 2 == 0 ? (width, height) : (height, width)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let rotation = try rotation(data)
        guard data.count >= baseOffset + width * height * 3 / 2 else { throw OwnDecodeError.truncated }
        let (outWidth, outHeight) = rotation % 2 == 0 ? (width, height) : (height, width)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress! + baseOffset
            for y in 0..<height {
                let pair = base + (y / 2) * width * 3
                let luma = pair + (y % 2) * width, c1 = pair + 2 * width, c2 = c1 + width / 2
                for x in 0..<width {
                    // Where the stored pixel (x, y) lands once turned upright.
                    let (ox, oy) = switch rotation {
                    case 1: (y, width - 1 - x)          // a quarter turn counter-clockwise
                    case 2: (width - 1 - x, height - 1 - y)
                    case 3: (height - 1 - y, x)         // a quarter turn clockwise
                    default: (x, y)
                    }
                    let i = (oy * outWidth + ox) * 4
                    let (r, g, b) = rgb(luma[x], c1[x / 2], c2[x / 2])
                    pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
                }
            }
        }
        return RGBAImage(width: outWidth, height: outHeight, pixels: pixels)
    }

    /// PhotoYCC to RGB (Kodak's published scale and offsets), clipped to 0…255.
    private static func rgb(_ y: UInt8, _ c1: UInt8, _ c2: UInt8) -> (UInt8, UInt8, UInt8) {
        let l = 1.3584 * Double(y), cb = 2.2179 * (Double(c1) - 156), cr = 1.8215 * (Double(c2) - 137)
        func clip(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return (clip(l + cr), clip(l - 0.194 * cb - 0.509 * cr), clip(l + cb))
    }

    private static func rotation(_ data: Data) throws -> Int {
        guard data.count > 0xE02, data[data.startIndex + 0x800..<data.startIndex + 0x807].elementsEqual("PCD_IPI".utf8)
        else { throw OwnDecodeError.notThisFormat }
        return Int(data[data.startIndex + 0xE02] & 3)
    }
}
