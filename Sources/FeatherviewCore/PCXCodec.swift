import Foundation

/// ZSoft PCX, and DCX (several PCX pages behind an offset table), written from ZSoft's technical reference.
public enum PCXCodec {
    static let pcx = OwnFormat.raster(
        name: "PCX", extensions: ["pcx"],
        size: { data, _ in try size(data) },
        decode: { data, _ in try decode(data) })

    static let dcx = OwnFormat.raster(
        name: "DCX", extensions: ["dcx"], hasPages: true,
        size: { data, page in try size(dcxPage(data, page)) },
        pageCount: dcxPageCount,
        decode: { data, page in try decode(dcxPage(data, page)) })

    private struct Header {
        let width, height, bitsPerPixel, planes, bytesPerLine: Int
        let compressed: Bool
        let ega: [UInt8]
    }

    private static func header(_ bytes: [UInt8]) throws -> Header {
        var reader = ByteReader(bytes)
        guard try reader.u8() == 0x0A else { throw OwnDecodeError.notThisFormat }
        try reader.skip(1)  // version: the fields we read mean the same in all of them
        let encoding = try reader.u8()
        let bitsPerPixel = Int(try reader.u8())
        let xMin = try reader.u16le(), yMin = try reader.u16le(), xMax = try reader.u16le(), yMax = try reader.u16le()
        try reader.skip(4)  // dpi
        let ega = Array(try reader.take(48))
        try reader.skip(1)
        let planes = Int(try reader.u8())
        let bytesPerLine = try reader.u16le()
        try reader.skip(60)
        guard encoding <= 1, xMax >= xMin, yMax >= yMin else { throw OwnDecodeError.corrupt }
        let (width, height) = try checkedSize(xMax - xMin + 1, yMax - yMin + 1)
        switch (bitsPerPixel, planes) {
        case (1, 1...4), (4, 1), (8, 1), (8, 3), (8, 4): break
        default: throw OwnDecodeError.unsupported
        }
        guard bytesPerLine * 8 >= width * bitsPerPixel else { throw OwnDecodeError.corrupt }
        return Header(width: width, height: height, bitsPerPixel: bitsPerPixel, planes: planes,
                      bytesPerLine: bytesPerLine, compressed: encoding == 1, ega: ega)
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        let h = try header([UInt8](data.prefix(128)))
        return (h.width, h.height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let bytes = [UInt8](data)
        let h = try header(bytes)
        let lineBytes = h.bytesPerLine * h.planes, total = lineBytes * h.height
        var reader = ByteReader(bytes)
        reader.offset = 128
        var raw: [UInt8]
        if h.compressed {
            raw = []
            raw.reserveCapacity(min(total, bytes.count * 63))  // a lying header can't reserve more than the data can expand to
            // Decoded as one stream: some writers let runs cross scanline and plane boundaries.
            while raw.count < total {
                let byte = try reader.u8()
                if byte >= 0xC0 {
                    raw.append(contentsOf: repeatElement(try reader.u8(), count: Int(byte & 0x3F)))
                } else {
                    raw.append(byte)
                }
            }
        } else {
            raw = Array(try reader.take(total))
        }

        var palette: [UInt8]? = nil  // 256 colours after a 0x0C marker at the very end
        if h.bitsPerPixel == 8, h.planes == 1, bytes.count - 769 >= 128, bytes[bytes.count - 769] == 0x0C {
            palette = Array(bytes[(bytes.count - 768)...])
        }

        var image = RGBAImage(width: h.width, height: h.height)
        let bpl = h.bytesPerLine
        for y in 0..<h.height {
            let line = y * lineBytes
            for x in 0..<h.width {
                let o = (y * h.width + x) * 4
                func set(_ table: [UInt8], _ index: Int) {
                    image.pixels[o] = table[index * 3]; image.pixels[o + 1] = table[index * 3 + 1]; image.pixels[o + 2] = table[index * 3 + 2]
                }
                switch (h.bitsPerPixel, h.planes) {
                case (1, 1):
                    let v: UInt8 = raw[line + x >> 3] >> (7 - x & 7) & 1 == 1 ? 255 : 0
                    image.pixels[o] = v; image.pixels[o + 1] = v; image.pixels[o + 2] = v
                case (1, _):
                    var index = 0
                    for p in 0..<h.planes { index |= Int(raw[line + p * bpl + x >> 3] >> (7 - x & 7) & 1) << p }
                    set(h.ega, index)
                case (4, _):
                    set(h.ega, Int(raw[line + x >> 1] >> (x & 1 == 0 ? 4 : 0) & 0x0F))
                case (8, 1):
                    let index = raw[line + x]
                    if let palette { set(palette, Int(index)) } else {
                        image.pixels[o] = index; image.pixels[o + 1] = index; image.pixels[o + 2] = index
                    }
                default:
                    for p in 0..<h.planes { image.pixels[o + p] = raw[line + p * bpl + x] }
                }
            }
        }
        return image
    }

    // MARK: DCX

    private static func dcxOffsets(_ data: Data) throws -> [Int] {
        var reader = ByteReader(data.prefix(4 + 1024 * 4))
        guard try reader.u32le() == 0x3ADE68B1 else { throw OwnDecodeError.notThisFormat }
        var offsets: [Int] = []
        while offsets.count < 1023 {
            let offset = try reader.u32le()
            if offset == 0 { break }
            offsets.append(offset)
        }
        return offsets
    }

    static func dcxPageCount(_ data: Data) -> Int { (try? dcxOffsets(data).count) ?? 0 }

    static func dcxPage(_ data: Data, _ page: Int) throws -> Data {
        let offsets = try dcxOffsets(data)
        guard offsets.indices.contains(page) else { throw OwnDecodeError.corrupt }
        let start = offsets[page]
        // A page ends where the next one starts (the table needn't be in order): the 256-colour palette is found from the end.
        let end = offsets.filter { $0 > start }.min() ?? data.count
        guard end <= data.count else { throw OwnDecodeError.truncated }
        return Data(data[data.startIndex + start..<data.startIndex + end])
    }

    // MARK: Encoding

    /// Version 5, 24-bit (three 8-bit planes), RLE, 72 dpi. Alpha is dropped: PCX readers rarely know a fourth plane.
    public static func encode(_ image: RGBAImage) -> Data {
        let width = image.width, bytesPerLine = (width + 1) & ~1  // the reference asks for an even count
        var out = [UInt8](repeating: 0, count: 128)
        func put16(_ value: Int, at i: Int) { out[i] = UInt8(value & 0xFF); out[i + 1] = UInt8(value >> 8 & 0xFF) }
        out[0] = 0x0A; out[1] = 5; out[2] = 1; out[3] = 8
        put16(width - 1, at: 8); put16(image.height - 1, at: 10)
        put16(72, at: 12); put16(72, at: 14)
        out[65] = 3
        put16(bytesPerLine, at: 66)
        put16(1, at: 68)  // colour palette info

        var line = [UInt8](repeating: 0, count: bytesPerLine)
        for y in 0..<image.height {
            for c in 0..<3 {
                for x in 0..<width { line[x] = image.pixels[(y * width + x) * 4 + c] }
                // Each plane's line is encoded on its own: older readers expect runs to stop there.
                var i = 0
                while i < line.count {
                    let value = line[i]
                    var count = 1
                    while count < 63, i + count < line.count, line[i + count] == value { count += 1 }
                    if count > 1 || value >= 0xC0 { out += [0xC0 | UInt8(count), value] } else { out.append(value) }
                    i += count
                }
            }
        }
        return Data(out)
    }
}
