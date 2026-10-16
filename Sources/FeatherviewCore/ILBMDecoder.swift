import Foundation

/// IFF ILBM (Amiga bitplanes, incl. EHB and HAM) and PBM (Deluxe Paint's chunky 8-bit variant).
enum ILBMDecoder {
    static let format = OwnFormat.raster(name: "IFF ILBM", extensions: ["iff", "lbm", "ilbm"],
                                         size: { data, _ in try size(data) },
                                         decode: { data, _ in try decode(data) })

    private struct Header {
        let width, height, planes, masking, compression, transparentColor: Int
    }

    private struct File {
        var isPBM = false
        var header: Header?
        var cmap: ArraySlice<UInt8> = []
        var camg = 0
        var body: ArraySlice<UInt8>?
    }

    private static func fourCC(_ reader: inout ByteReader) throws -> String {
        String(decoding: try reader.take(4), as: UTF8.self)
    }

    private static func parse(_ data: Data, headerOnly: Bool) throws -> File {
        var reader = ByteReader(data)
        guard reader.remaining >= 12, try fourCC(&reader) == "FORM" else { throw OwnDecodeError.notThisFormat }
        let end = min(reader.data.count, 8 + (try reader.u32be()))
        let kind = try fourCC(&reader)
        guard kind == "ILBM" || kind == "PBM " else { throw OwnDecodeError.notThisFormat }
        var file = File(isPBM: kind == "PBM ")
        while reader.offset + 8 <= end {
            let id = try fourCC(&reader)
            let length = try reader.u32be()
            let chunk = try reader.take(length)
            if length % 2 == 1, !reader.isAtEnd { try reader.skip(1) }  // chunks are padded to even length
            switch id {
            case "BMHD":
                guard length >= 20 else { throw OwnDecodeError.corrupt }
                var r = ByteReader(Array(chunk))
                let width = try r.u16be(), height = try r.u16be()
                try r.skip(4)  // x, y
                let planes = Int(try r.u8()), masking = Int(try r.u8()), compression = Int(try r.u8())
                try r.skip(1)
                file.header = Header(width: width, height: height, planes: planes, masking: masking,
                                     compression: compression, transparentColor: try r.u16be())
                if headerOnly { return file }
            case "CMAP": file.cmap = chunk
            case "CAMG" where length >= 4: var r = ByteReader(Array(chunk)); file.camg = try r.u32be()
            case "BODY": file.body = chunk
            default: break
            }
        }
        return file
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        guard let h = try parse(data, headerOnly: true).header else { throw OwnDecodeError.corrupt }
        let (width, height) = try checkedSize(h.width, h.height)
        return (width, height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let file = try parse(data, headerOnly: false)
        guard let h = file.header, let bodyBytes = file.body else { throw OwnDecodeError.corrupt }
        let (width, height) = try checkedSize(h.width, h.height)
        guard h.compression <= 1 else { throw OwnDecodeError.unsupported }
        guard file.isPBM ? h.planes == 8 : (1...8).contains(h.planes) || h.planes == 24
        else { throw OwnDecodeError.unsupported }

        let ham = !file.isPBM && file.camg & 0x800 != 0 && (h.planes == 6 || h.planes == 8)
        let ehb = !file.isPBM && file.camg & 0x80 != 0 && h.planes == 6
        let hasMask = !file.isPBM && h.masking == 1
        let planeRowBytes = file.isPBM ? (width + 1) / 2 * 2 : (width + 15) / 16 * 2
        let rowBytes = file.isPBM ? planeRowBytes : planeRowBytes * (h.planes + (hasMask ? 1 : 0))

        var reader = ByteReader(Array(bodyBytes))
        let body = h.compression == 1 ? try unpackByteRun1(&reader, count: rowBytes * height)
                                      : Array(try reader.take(rowBytes * height))

        var palette: [(UInt8, UInt8, UInt8)] = stride(from: file.cmap.startIndex, to: file.cmap.endIndex - 2, by: 3)
            .map { (file.cmap[$0], file.cmap[$0 + 1], file.cmap[$0 + 2]) }
        if palette.isEmpty, h.planes <= 8 {
            let top = (1 << h.planes) - 1
            palette = (0...top).map { let v = UInt8($0 * 255 / max(top, 1)); return (v, v, v) }
        }
        if ehb {
            palette = Array(palette.prefix(32))
            palette += palette.map { ($0.0 / 2, $0.1 / 2, $0.2 / 2) }
        }
        func color(_ i: Int) -> (UInt8, UInt8, UInt8) { i < palette.count ? palette[i] : (0, 0, 0) }

        let valueBits = h.planes - 2
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let row = y * rowBytes
            var previous = color(0)  // HAM starts each row from the background colour
            for x in 0..<width {
                func bit(_ plane: Int) -> Int { Int(body[row + plane * planeRowBytes + x / 8] >> (7 - x % 8) & 1) }
                let index: Int
                if file.isPBM { index = Int(body[row + x]) } else {
                    var v = 0
                    for p in 0..<h.planes { v |= bit(p) << p }
                    index = v
                }
                var c: (UInt8, UInt8, UInt8)
                if h.planes == 24 {
                    c = (UInt8(index & 0xFF), UInt8(index >> 8 & 0xFF), UInt8(index >> 16))
                } else if ham {
                    let value = index & (1 << valueBits - 1)
                    // HAM6 sets a component's 4 bits (×17 spreads them to 8); HAM8 sets the top 6 and keeps the low 2.
                    func modify(_ old: UInt8) -> UInt8 {
                        valueBits == 4 ? UInt8(value * 17) : UInt8(value << 2 | Int(old) & 3)
                    }
                    c = previous
                    switch index >> valueBits {
                    case 0: c = color(value)
                    case 1: c.2 = modify(c.2)
                    case 2: c.0 = modify(c.0)
                    default: c.1 = modify(c.1)
                    }
                    previous = c
                } else {
                    c = color(index)
                }
                var alpha: UInt8 = 255
                if hasMask, bit(h.planes) == 0 { alpha = 0 }
                if h.masking == 2, !ham, h.planes != 24, index == h.transparentColor { alpha = 0 }
                image[x, y] = (c.0, c.1, c.2, alpha)
            }
        }
        return image
    }

    /// ByteRun1 (PackBits): n ≥ 0 copies n + 1 bytes, n < 0 repeats the next byte 1 − n times, −128 does
    /// nothing. Runs that cross rows are tolerated; nothing is written past `count`.
    static func unpackByteRun1(_ reader: inout ByteReader, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(min(count, reader.remaining * 128))  // 2 input bytes expand to at most 128
        while out.count < count {
            let n = Int(Int8(bitPattern: try reader.u8()))
            if n >= 0 {
                out.append(contentsOf: try reader.take(n + 1).prefix(count - out.count))
            } else if n != -128 {
                out.append(contentsOf: repeatElement(try reader.u8(), count: min(1 - n, count - out.count)))
            }
        }
        return out
    }
}
