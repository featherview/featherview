import Foundation

/// Binary PGM (P5) and PPM (P6), 8 bits per sample. Alpha is dropped.
public enum NetpbmEncoder {
    public static func pgm(_ image: RGBAImage) -> Data {
        var data = Data("P5\n\(image.width) \(image.height)\n255\n".utf8)
        data.reserveCapacity(data.count + image.width * image.height)
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            let r = Int(image.pixels[i]), g = Int(image.pixels[i + 1]), b = Int(image.pixels[i + 2])
            data.append(UInt8((299 * r + 587 * g + 114 * b + 500) / 1000))  // BT.601 luma, rounded
        }
        return data
    }

    public static func ppm(_ image: RGBAImage) -> Data {
        var data = Data("P6\n\(image.width) \(image.height)\n255\n".utf8)
        data.reserveCapacity(data.count + image.width * image.height * 3)
        for i in stride(from: 0, to: image.pixels.count, by: 4) { data.append(contentsOf: image.pixels[i..<i + 3]) }
        return data
    }
}
