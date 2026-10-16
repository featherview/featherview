import Foundation

/// PBM (P1, 1 bit), binary PGM (P5) and PPM (P6, 8 bits per sample). Alpha is dropped.
public enum NetpbmEncoder {
    /// Plain PBM (P1): the only PBM ImageIO reads, so Featherview and Preview open it. Black (1) where
    /// the luma is below half, else white; one line per row, at most 70 characters.
    public static func pbm(_ image: RGBAImage) -> Data {
        var data = Data("P1\n\(image.width) \(image.height)\n".utf8)
        data.reserveCapacity(data.count + (image.width + image.width / 70 + 1) * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                data.append(luma(image, y * image.width + x) < 128 ? UInt8(ascii: "1") : UInt8(ascii: "0"))
                if x % 70 == 69 || x == image.width - 1 { data.append(UInt8(ascii: "\n")) }
            }
        }
        return data
    }

    public static func pgm(_ image: RGBAImage) -> Data {
        var data = Data("P5\n\(image.width) \(image.height)\n255\n".utf8)
        data.reserveCapacity(data.count + image.width * image.height)
        for pixel in 0..<image.width * image.height { data.append(UInt8(luma(image, pixel))) }
        return data
    }

    public static func ppm(_ image: RGBAImage) -> Data {
        var data = Data("P6\n\(image.width) \(image.height)\n255\n".utf8)
        data.reserveCapacity(data.count + image.width * image.height * 3)
        for i in stride(from: 0, to: image.pixels.count, by: 4) { data.append(contentsOf: image.pixels[i..<i + 3]) }
        return data
    }

    /// BT.601 luma, rounded.
    private static func luma(_ image: RGBAImage, _ pixel: Int) -> Int {
        let i = pixel * 4
        let r = Int(image.pixels[i]), g = Int(image.pixels[i + 1]), b = Int(image.pixels[i + 2])
        return (299 * r + 587 * g + 114 * b + 500) / 1000
    }
}
