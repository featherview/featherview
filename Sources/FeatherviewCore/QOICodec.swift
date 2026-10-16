import Foundation

/// QOI, "Quite OK Image" (qoiformat.org, specification v1.0).
public enum QOICodec {
    static let format = OwnFormat.raster(name: "QOI", extensions: ["qoi"],
                                         size: { data, _ in try size(data) },
                                         decode: { data, _ in try decode(data) })

    private static let magic: [UInt8] = Array("qoif".utf8)
    private static let endMarker: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]

    private struct Pixel: Equatable {
        var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
        var hash: Int { (Int(r) * 3 + Int(g) * 5 + Int(b) * 7 + Int(a) * 11) % 64 }
    }

    private static func header(_ reader: inout ByteReader) throws -> (width: Int, height: Int) {
        guard Array(try reader.take(4)) == magic else { throw OwnDecodeError.notThisFormat }
        let width = try reader.u32be(), height = try reader.u32be()
        let channels = try reader.u8(), colorspace = try reader.u8()
        guard channels == 3 || channels == 4, colorspace <= 1 else { throw OwnDecodeError.corrupt }
        return try checkedSize(width, height)
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        return try header(&reader)
    }

    /// The end marker isn't checked: a file whose pixels are all there is shown even without it.
    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let (width, height) = try header(&reader)
        let count = width * height
        // One RUN byte covers at most 62 pixels: a short file can't make us allocate its claimed size.
        guard count <= reader.remaining * 62 else { throw OwnDecodeError.truncated }
        var pixels = [UInt8](repeating: 0, count: count * 4)
        var index = [Pixel](repeating: Pixel(a: 0), count: 64)
        var px = Pixel()
        var run = 0
        for i in 0..<count {
            if run > 0 {
                run -= 1
            } else {
                let op = try reader.u8()
                switch op {
                case 0xFE: px.r = try reader.u8(); px.g = try reader.u8(); px.b = try reader.u8()
                case 0xFF: px.r = try reader.u8(); px.g = try reader.u8(); px.b = try reader.u8(); px.a = try reader.u8()
                case 0x00..<0x40: px = index[Int(op)]
                case 0x40..<0x80:
                    px.r &+= (op >> 4 & 3) &- 2; px.g &+= (op >> 2 & 3) &- 2; px.b &+= (op & 3) &- 2
                case 0x80..<0xC0:
                    let next = try reader.u8()
                    let vg = (op & 0x3F) &- 32
                    px.r &+= vg &- 8 &+ (next >> 4); px.g &+= vg; px.b &+= vg &- 8 &+ (next & 0x0F)
                default: run = Int(op & 0x3F)
                }
                index[px.hash] = px
            }
            pixels[i * 4] = px.r; pixels[i * 4 + 1] = px.g; pixels[i * 4 + 2] = px.b; pixels[i * 4 + 3] = px.a
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Always 4 channels, colorspace 0. Ops are chosen in the reference encoder's order, so output matches it byte for byte.
    public static func encode(_ image: RGBAImage) -> Data {
        var out = magic
        out.reserveCapacity(14 + image.width * image.height * 5 + 8)
        for value in [image.width, image.height] {
            for shift in [24, 16, 8, 0] { out.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        out += [4, 0]
        var index = [Pixel](repeating: Pixel(a: 0), count: 64)
        var prev = Pixel()
        var run = 0
        let p = image.pixels, count = image.width * image.height
        func delta(_ a: UInt8, _ b: UInt8) -> Int { Int(Int8(bitPattern: a &- b)) }
        for i in 0..<count {
            let px = Pixel(r: p[i * 4], g: p[i * 4 + 1], b: p[i * 4 + 2], a: p[i * 4 + 3])
            if px == prev {
                run += 1
                if run == 62 || i == count - 1 { out.append(0xC0 | UInt8(run - 1)); run = 0 }
                continue
            }
            if run > 0 { out.append(0xC0 | UInt8(run - 1)); run = 0 }
            let hash = px.hash
            if index[hash] == px {
                out.append(UInt8(hash))
            } else {
                index[hash] = px
                if px.a == prev.a {
                    let vr = delta(px.r, prev.r), vg = delta(px.g, prev.g), vb = delta(px.b, prev.b)
                    let vgr = vr - vg, vgb = vb - vg
                    if (-2...1).contains(vr), (-2...1).contains(vg), (-2...1).contains(vb) {
                        out.append(0x40 | UInt8(vr + 2) << 4 | UInt8(vg + 2) << 2 | UInt8(vb + 2))
                    } else if (-8...7).contains(vgr), (-32...31).contains(vg), (-8...7).contains(vgb) {
                        out += [0x80 | UInt8(vg + 32), UInt8(vgr + 8) << 4 | UInt8(vgb + 8)]
                    } else {
                        out += [0xFE, px.r, px.g, px.b]
                    }
                } else {
                    out += [0xFF, px.r, px.g, px.b, px.a]
                }
            }
            prev = px
        }
        return Data(out + endMarker)
    }
}
