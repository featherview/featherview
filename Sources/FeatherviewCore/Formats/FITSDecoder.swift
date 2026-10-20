import Foundation

/// FITS (astronomy): headers of 80-character cards in 2880-byte blocks, then big-endian samples, the
/// first row at the bottom. Shows the first image in the file (the primary one, or the first IMAGE
/// extension when the primary holds none): its first plane, or three planes as red, green, blue.
/// 8-bit data shows as stored; everything else is stretched linearly between the 0.25th and 99.75th
/// percentile, so a few hot pixels don't turn the picture black.
// shortcut: tile-compressed images (ZIMAGE tables) can't be opened, decode them if astronomers ask.
enum FITSDecoder {
    static let format = OwnFormat.raster(name: "FITS", extensions: ["fits", "fit", "fts"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    private struct Image {
        let bitpix, width, height, planes, dataOffset: Int
        let zero, scale: Double
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        let image = try firstImage(data)
        return (image.width, image.height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let h = try firstImage(data)
        let bytes = abs(h.bitpix) / 8, pixels = h.width * h.height, planes = h.planes == 3 ? 3 : 1
        guard data.count - h.dataOffset >= pixels * planes * bytes else { throw OwnDecodeError.truncated }  // before allocating
        var reader = ByteReader(data)
        reader.offset = h.dataOffset
        let raw = try reader.take(pixels * planes * bytes)
        let values: [Double] = raw.withUnsafeBufferPointer { buffer in
            (0..<pixels * planes).map { i in
                var bits: UInt64 = 0
                for b in 0..<bytes { bits = bits << 8 | UInt64(buffer[i * bytes + b]) }
                let stored: Double = switch h.bitpix {
                case 8: Double(bits)
                case 16: Double(Int16(truncatingIfNeeded: bits))
                case 32: Double(Int32(truncatingIfNeeded: bits))
                case 64: Double(Int64(bitPattern: bits))
                case -32: Double(Float(bitPattern: UInt32(bits)))
                default: Double(bitPattern: bits)
                }
                return h.zero + h.scale * stored
            }
        }
        let (low, high) = h.bitpix == 8 && h.zero == 0 && h.scale == 1 ? (0.0, 255.0) : range(values)
        let span = high > low ? high - low : 1
        var image = RGBAImage(width: h.width, height: h.height)
        image.pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<h.height {
                let row = (h.height - 1 - y) * h.width
                for x in 0..<h.width {
                    for c in 0..<3 {
                        let v = values[(planes == 3 ? c * pixels : 0) + row + x]
                        out[(y * h.width + x) * 4 + c] = v.isFinite ? UInt8(max(0, min(255, ((v - low) / span * 255).rounded()))) : 0
                    }
                }
            }
        }
        return image
    }

    /// The 0.25th and 99.75th percentile of the finite values, from a sample of at most a million.
    private static func range(_ values: [Double]) -> (Double, Double) {
        let step = max(1, values.count / 1_000_000)
        let sample = stride(from: 0, to: values.count, by: step).map { values[$0] }.filter(\.isFinite).sorted()
        guard !sample.isEmpty else { return (0, 1) }
        let last = Double(sample.count - 1)
        return (sample[Int(last * 0.0025)], sample[Int((last * 0.9975).rounded())])
    }

    /// Walks the header-data units until one holds an image of at least two axes.
    private static func firstImage(_ data: Data) throws -> Image {
        var offset = 0
        while true {
            var cards: [String: String] = [:]
            var reader = ByteReader(data)
            reader.offset = offset
            var first = true
            while true {
                let card = String(decoding: try reader.take(80), as: UTF8.self)
                let key = card.prefix(8).trimmingCharacters(in: .whitespaces)
                if first {
                    guard offset == 0 ? key == "SIMPLE" : key == "XTENSION" else { throw OwnDecodeError.notThisFormat }
                    first = false
                }
                if key == "END" { break }
                guard card.dropFirst(8).hasPrefix("= ") else { continue }
                let value = card.dropFirst(10).split(separator: "/", maxSplits: 1).first ?? ""
                cards[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: " '"))
            }
            let dataOffset = (reader.offset + 2879) / 2880 * 2880
            guard let bitpix = cards["BITPIX"].flatMap({ Int($0) }), [8, 16, 32, 64, -32, -64].contains(bitpix),
                  let axes = cards["NAXIS"].flatMap({ Int($0) }), (0...999).contains(axes) else { throw OwnDecodeError.corrupt }
            let lengths = try (0..<axes).map { i -> Int in
                guard let n = cards["NAXIS\(i + 1)"].flatMap({ Int($0) }), (0...1 << 30).contains(n) else { throw OwnDecodeError.corrupt }
                return n
            }
            let isImage = offset == 0 || cards["XTENSION"] == "IMAGE"
            if isImage, axes >= 2 {
                let (width, height) = try checkedSize(lengths[0], lengths[1])
                return Image(bitpix: bitpix, width: width, height: height, planes: axes >= 3 ? lengths[2] : 1,
                             dataOffset: dataOffset, zero: cards["BZERO"].flatMap { Double($0) } ?? 0,
                             scale: cards["BSCALE"].flatMap { Double($0) } ?? 1)
            }
            if offset == 0, axes == 1 { throw OwnDecodeError.unsupported }  // a spectrum, not a picture
            // Skip this unit's data (and a table's heap) to the next header.
            let groups = cards["GCOUNT"].flatMap { Int($0) } ?? 1, heap = cards["PCOUNT"].flatMap { Int($0) } ?? 0
            // In Double, so hostile header values can't overflow.
            let elements = lengths.isEmpty ? 0 : lengths.reduce(1.0) { $0 * Double($1) }
            let bytes = (elements + Double(heap)) * Double(groups) * Double(abs(bitpix) / 8)
            guard groups >= 0, heap >= 0, bytes < Double(data.count) else { throw OwnDecodeError.corrupt }
            let size = Int(bytes)
            offset = dataOffset + (size + 2879) / 2880 * 2880
            guard offset < data.count else { throw OwnDecodeError.unsupported }  // no image in the file
        }
    }
}
