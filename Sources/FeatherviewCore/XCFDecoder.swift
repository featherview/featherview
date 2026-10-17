import Foundation

/// GIMP's XCF, shown flattened: the visible top-level layers composited bottom first (spec "Formats").
/// A layer group's own hierarchy is its rendered projection, so the group's children are never drawn.
// shortcut: blend modes other than normal are drawn as normal, implement the common ones (multiply, screen) if users ask.
// shortcut: layer effects (XCF 20+) aren't applied, the stored pixels are from before the effects; render them if real files need it.
// shortcut: .xcf.gz / .xcf.bz2 aren't read (their extension is gz / bz2, not an image), open them by inner extension if users ask.
// Text layers show their stored pixels, which is what GIMP rendered: correct as it is.
enum XCFDecoder {
    static let format = OwnFormat.raster(name: "GIMP XCF", extensions: ["xcf"],
                                         size: { data, _ in try size(data) },
                                         decode: { data, _ in try decode(data) })

    private struct Precision {
        var bytes = 1, isFloat = false, isLinear = false
    }

    private struct Header {
        var version: Int, width: Int, height: Int, precision: Precision
    }

    private static func header(_ reader: inout ByteReader) throws -> Header {
        guard reader.remaining >= 14, Array(try reader.take(9)) == Array("gimp xcf ".utf8) else { throw OwnDecodeError.notThisFormat }
        let tag = String(decoding: try reader.take(4), as: UTF8.self)
        let version: Int
        if tag == "file" {
            version = 0
        } else if tag.first == "v", tag.dropFirst().allSatisfy(\.isASCII), let v = Int(tag.dropFirst()), v >= 0 {
            version = v
        } else {
            throw OwnDecodeError.notThisFormat
        }
        guard try reader.u8() == 0 else { throw OwnDecodeError.notThisFormat }
        let width = try reader.u32be(), height = try reader.u32be()
        guard try reader.u32be() <= 2 else { throw OwnDecodeError.unsupported }  // base type: RGB, gray, indexed
        let precision = version >= 4 ? try Self.precision(try reader.u32be(), version: version) : Precision()
        // Versions 7 to 11 above 8 bits come from GIMP development builds, whose byte order isn't known.
        if (7...11).contains(version), precision.bytes > 1 { throw OwnDecodeError.unsupported }
        return Header(version: version, width: width, height: height, precision: precision)
    }

    private static func precision(_ value: Int, version: Int) throws -> Precision {
        if version == 4 {
            switch value {
            case 0: return Precision()
            case 1: return Precision(bytes: 2)
            case 2: return Precision(bytes: 4, isLinear: true)
            case 3: return Precision(bytes: 2, isFloat: true, isLinear: true)
            case 4: return Precision(bytes: 4, isFloat: true, isLinear: true)
            default: throw OwnDecodeError.unsupported
            }
        }
        let isLinear = value % 100 == 0
        switch (value, version >= 7) {
        case (100, _), (150, _): return Precision(bytes: 1, isLinear: isLinear)
        case (200, _), (250, _): return Precision(bytes: 2, isLinear: isLinear)
        case (300, _), (350, _): return Precision(bytes: 4, isLinear: isLinear)
        case (400, false), (450, false), (500, true), (550, true): return Precision(bytes: 2, isFloat: true, isLinear: isLinear)
        case (500, false), (550, false), (600, true), (650, true): return Precision(bytes: 4, isFloat: true, isLinear: isLinear)
        case (700, true), (750, true): return Precision(bytes: 8, isFloat: true, isLinear: isLinear)
        default: throw OwnDecodeError.unsupported
        }
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        let h = try header(&reader)
        let (width, height) = try checkedSize(h.width, h.height)
        return (width, height)
    }

    private static func skip(_ reader: inout ByteReader, _ count: Int) throws {
        guard count >= 0, count <= reader.remaining else { throw OwnDecodeError.truncated }
        reader.offset += count
    }

    private static func skipString(_ reader: inout ByteReader) throws { try skip(&reader, try reader.u32be()) }

    /// Reads a property list up to `PROP_END`; `body` gets each property's type and a reader over its payload.
    private static func properties(_ reader: inout ByteReader, version: Int,
                                   _ body: (Int, inout ByteReader) throws -> Void) throws {
        while true {
            let type = try reader.u32be(), length = try reader.u32be()
            if type == 0 { return }
            var end = reader.offset + length
            var fields = reader
            switch type {
            case 1:  // PROP_COLORMAP: some GIMP versions wrote n + 4 as the length, the payload is always 3n + 4
                end = reader.offset + 4 + 3 * (try fields.u32be())
            case 24:  // PROP_USER_UNIT: GIMP wrote a wrong length for decades, so read it by its fields
                try skip(&fields, 8)
                for _ in 0..<(version >= 21 ? 3 : 5) { try skipString(&fields) }
                end = fields.offset
            default: break
            }
            guard end <= reader.data.count else { throw OwnDecodeError.truncated }
            let start = reader.data.startIndex
            var payload = ByteReader(reader.data[start + reader.offset..<start + end])
            try body(type, &payload)
            reader.offset = end
        }
    }

    private struct Layer {
        var width = 0, height = 0, type = 0, x = 0, y = 0
        var visible = true, opacity = 1.0, applyMask = true, depth = 1
        var hierarchy = 0, mask = 0

        /// Bytes per pixel in a tile: colour components, then alpha, each at the precision.
        func bpp(_ precision: Precision) -> Int { ((type / 2 == 0 ? 3 : 1) + type % 2) * precision.bytes }
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let h = try header(&reader)
        var palette: [UInt8] = [], compression = 0
        try properties(&reader, version: h.version) { type, p in
            switch type {
            case 1: palette = Array(try p.take(3 * (try p.u32be())))  // used by indexed images only
            case 17: compression = Int(try p.u8())
            default: break
            }
        }
        guard compression <= 2 else { throw OwnDecodeError.unsupported }
        let file = File(data: data, wide: h.version >= 11, compression: compression, palette: palette)
        var layers: [Int] = []
        while true {
            let p = try file.pointer(&reader)
            if p == 0 { break }
            layers.append(p)
        }
        file.minPointer = reader.offset
        guard Set(layers).count == layers.count else { throw OwnDecodeError.corrupt }  // GIMP writes each layer once

        // Only the stored tiles of a layer are decoded and drawn, and each 64 × 64 tile (16 KiB of RGBA) costs at
        // least its 4-byte pointer, so layers can't make us fill much more than 4096 bytes per byte of the file.
        // The canvas has no tiles, so it gets 32 times that (128 KiB per byte): the few hundred bytes of the smallest
        // real file with one layer open a 3000 × 3000 canvas, but a 1 GB canvas needs at least an 8 KiB file.
        var budget = data.count * 4096, hierarchies: Set<Int> = []
        let (width, height) = try checkedSize(h.width, h.height)
        guard width * height * 4 <= data.count * 131072 else { throw OwnDecodeError.corrupt }
        var canvas = try LayerCanvas(width: width, height: height)
        for pointer in layers.reversed() {  // the list is topmost first
            let layer = try file.layer(at: pointer, version: h.version)
            // Children of a group are inside the group's projection; only top-level items are drawn.
            guard layer.visible, layer.depth <= 1, layer.opacity > 0 else { continue }
            // GIMP's own layer limit; only the part on the canvas is decoded, so a layer may be larger than our image cap.
            guard (1...524_288).contains(layer.width), (1...524_288).contains(layer.height) else { throw OwnDecodeError.corrupt }
            guard layer.type <= 5 else { throw OwnDecodeError.unsupported }
            // Only the part of the layer on the canvas is decoded, so memory stays at the canvas size.
            // GIMP writes each hierarchy once; shared ones would draw tiles the file paid for once many times.
            guard hierarchies.insert(layer.hierarchy).inserted else { throw OwnDecodeError.corrupt }
            let precision = layer.type >= 4 ? Precision() : h.precision  // indexed is always 8-bit
            let pointers = try file.tilePointers(of: layer.hierarchy, width: layer.width, height: layer.height,
                                                 bpp: layer.bpp(precision))
            // Stored tiles come first in row-major order: clip to the rows (and, within the first row, the
            // columns) they cover; the empty rest isn't drawn.
            let columns = (layer.width + 63) / 64, rows = (pointers.count + columns - 1) / columns
            let x0 = max(0, -layer.x), x1 = min(layer.width, h.width - layer.x, rows > 1 ? .max : pointers.count * 64)
            let y0 = max(0, -layer.y), y1 = min(layer.height, h.height - layer.y, rows * 64)
            guard x0 < x1, y0 < y1 else { continue }
            let region = Region(x0: x0, y0: y0, x1: x1, y1: y1)
            budget -= region.width * region.height * 4
            guard budget >= 0 else { throw OwnDecodeError.corrupt }
            var image = try file.pixels(of: layer, pointers: pointers, region: region, precision: precision)
            if layer.mask != 0, layer.applyMask {
                try file.applyMask(at: layer.mask, of: layer, region: region, precision: precision, to: &image)
            }
            canvas.draw(image, x: layer.x + x0, y: layer.y + y0, opacity: layer.opacity)
        }
        return canvas.image
    }

    private struct Region { var x0, y0, x1, y1: Int; var width: Int { x1 - x0 }; var height: Int { y1 - y0 } }

    private final class File {
        let data: Data, wide: Bool, compression: Int, palette: [UInt8]
        /// Every structure comes after the image header's pointer list; a pointer before it is a loop.
        var minPointer = 0
        /// Bytes of tile pointers and properties left to read. A real file stores each once, so it never reads
        /// more than its own size; structures shared by crafted pointers would make parsing take minutes.
        private var work: Int

        init(data: Data, wide: Bool, compression: Int, palette: [UInt8]) {
            self.data = data; self.wide = wide; self.compression = compression; self.palette = palette
            work = data.count
        }

        func charge(_ bytes: Int) throws {
            work -= bytes
            guard work >= 0 else { throw OwnDecodeError.corrupt }
        }

        func pointer(_ reader: inout ByteReader) throws -> Int {
            wide ? try reader.u32be() << 32 | reader.u32be() : try reader.u32be()
        }

        func reader(at pointer: Int) throws -> ByteReader {
            guard pointer >= minPointer, pointer < data.count else { throw OwnDecodeError.corrupt }
            var reader = ByteReader(data)
            reader.offset = pointer
            return reader
        }

        func layer(at pointer: Int, version: Int) throws -> Layer {
            var r = try reader(at: pointer)
            var layer = Layer(width: try r.u32be(), height: try r.u32be(), type: try r.u32be())
            try skipString(&r)
            var floatOpacity: Double?
            try properties(&r, version: version) { type, p in
                try charge(8 + p.remaining)
                switch type {
                case 6: layer.opacity = Double(min(try p.u32be(), 255)) / 255
                case 8: layer.visible = try p.u32be() != 0
                case 11: layer.applyMask = try p.u32be() != 0
                case 15:
                    layer.x = Int(Int32(truncatingIfNeeded: try p.u32be()))
                    layer.y = Int(Int32(truncatingIfNeeded: try p.u32be()))
                case 30: layer.depth = p.remaining / 4  // PROP_ITEM_PATH: one entry per level of nesting
                case 33:
                    let value = Double(Float(bitPattern: UInt32(try p.u32be())))
                    if value.isFinite { floatOpacity = min(max(value, 0), 1) }
                // PROP_MODE (7) is noted but not used: every mode is drawn as normal. PROP_GROUP_ITEM (29)
                // needs nothing: a group's hierarchy is its projection.
                default: break
                }
            }
            if let floatOpacity { layer.opacity = floatOpacity }
            layer.hierarchy = try self.pointer(&r)
            layer.mask = try self.pointer(&r)
            return layer
        }

        /// The offsets of a hierarchy's stored tiles, row-major.
        func tilePointers(of pointer: Int, width: Int, height: Int, bpp: Int) throws -> [Int] {
            var r = try reader(at: pointer)
            guard try r.u32be() == width, try r.u32be() == height, try r.u32be() == bpp else { throw OwnDecodeError.corrupt }
            r = try reader(at: try self.pointer(&r))  // first level only
            guard try r.u32be() == width, try r.u32be() == height else { throw OwnDecodeError.corrupt }
            let columns = (width + 63) / 64, rows = (height + 63) / 64
            var pointers: [Int] = []
            // A list cut short by a 0 leaves the remaining tiles empty, as GIMP reads it.
            for _ in 0..<columns * rows {
                try charge(wide ? 8 : 4)
                let p = try self.pointer(&r)
                if p == 0 { break }
                guard p >= minPointer, p > (pointers.last ?? -1), data.count > p else { throw OwnDecodeError.corrupt }
                pointers.append(p)
            }
            return pointers
        }

        /// Calls `body` with each tile that overlaps `region` (layer coordinates), its bytes interleaved
        /// per pixel, its size and its top-left corner. A tile past the stored ones is empty: its buffer has no bytes.
        func tiles(_ pointers: [Int], width: Int, height: Int, bpp: Int, region: Region,
                   _ body: (_ tile: UnsafeBufferPointer<UInt8>, _ width: Int, _ height: Int, _ x: Int, _ y: Int) throws -> Void) throws {
            let columns = (width + 63) / 64, rows = (height + 63) / 64
            var tile = [UInt8](repeating: 0, count: 64 * 64 * bpp)
            try data.withUnsafeBytes { (file: UnsafeRawBufferPointer) in
                let bytes = file.bindMemory(to: UInt8.self)
                for row in 0..<rows {
                    let ty = row * 64, th = min(64, height - ty)
                    guard ty < region.y1, ty + th > region.y0 else { continue }
                    for column in 0..<columns {
                        let tx = column * 64, tw = min(64, width - tx)
                        guard tx < region.x1, tx + tw > region.x0 else { continue }
                        let i = row * columns + column, size = tw * th * bpp
                        guard i < pointers.count else {
                            try body(UnsafeBufferPointer(start: nil, count: 0), tw, th, tx, ty)
                            continue
                        }
                        let start = pointers[i]
                        // A tile ends where the next begins; the last one can't be longer than twice its pixels.
                        let end = i + 1 < pointers.count ? pointers[i + 1] : min(bytes.count, start + 2 * size + 64)
                        let source = UnsafeBufferPointer(rebasing: bytes[start..<end])
                        switch compression {
                        case 0:
                            guard source.count >= size else { throw OwnDecodeError.truncated }
                            tile.replaceSubrange(0..<size, with: source[0..<size])
                        case 1:
                            try unRLE(source, into: &tile, pixels: tw * th, bpp: bpp)
                        default:
                            let inflated = try Inflate.zlib(ArraySlice(source), size: size)
                            tile.replaceSubrange(0..<size, with: inflated)
                        }
                        try tile.withUnsafeBufferPointer { try body($0, tw, th, tx, ty) }
                    }
                }
            }
        }

        func pixels(of layer: Layer, pointers: [Int], region: Region, precision: Precision) throws -> RGBAImage {
            let colours = layer.type / 2 == 0 ? 3 : 1, hasAlpha = layer.type % 2 == 1, isIndexed = layer.type >= 4
            let bpp = layer.bpp(precision)
            var image = RGBAImage(width: region.width, height: region.height,
                                  pixels: [UInt8](repeating: 255, count: region.width * region.height * 4))
            let palette = self.palette
            try image.pixels.withUnsafeMutableBufferPointer { out in
                try tiles(pointers, width: layer.width, height: layer.height, bpp: bpp, region: region) { tile, tw, th, tx, ty in
                    if tile.isEmpty {  // transparent, also for a layer without alpha
                        for y in max(ty, region.y0)..<min(ty + th, region.y1) {
                            for x in max(tx, region.x0)..<min(tx + tw, region.x1) {
                                out[((y - region.y0) * region.width + (x - region.x0)) * 4 + 3] = 0
                            }
                        }
                        return
                    }
                    for y in max(ty, region.y0)..<min(ty + th, region.y1) {
                        for x in max(tx, region.x0)..<min(tx + tw, region.x1) {
                            let s = ((y - ty) * tw + (x - tx)) * bpp
                            let d = ((y - region.y0) * region.width + (x - region.x0)) * 4
                            if isIndexed {
                                let index = Int(tile[s]) * 3
                                for c in 0..<3 { out[d + c] = index + 2 < palette.count ? palette[index + c] : 0 }
                                if hasAlpha { out[d + 3] = tile[s + 1] < 128 ? 0 : 255 }
                                continue
                            }
                            for c in 0..<colours {
                                out[d + c] = byte(tile, s + c * precision.bytes, precision, colour: true)
                            }
                            if colours == 1 { out[d + 1] = out[d]; out[d + 2] = out[d] }
                            if hasAlpha { out[d + 3] = byte(tile, s + colours * precision.bytes, precision, colour: false) }
                        }
                    }
                }
            }
            return image
        }

        /// A layer mask is a channel the size of its layer: one gray component per pixel at the image
        /// precision, multiplied into the layer's alpha.
        func applyMask(at pointer: Int, of layer: Layer, region: Region, precision: Precision, to image: inout RGBAImage) throws {
            var r = try reader(at: pointer)
            guard try r.u32be() == layer.width, try r.u32be() == layer.height else { throw OwnDecodeError.corrupt }
            try skipString(&r)
            try properties(&r, version: 0) { _, p in try charge(8 + p.remaining) }
            let pointers = try tilePointers(of: try self.pointer(&r), width: layer.width, height: layer.height, bpp: precision.bytes)
            try image.pixels.withUnsafeMutableBufferPointer { out in
                try tiles(pointers, width: layer.width, height: layer.height, bpp: precision.bytes, region: region) { tile, tw, th, tx, ty in
                    for y in max(ty, region.y0)..<min(ty + th, region.y1) {
                        for x in max(tx, region.x0)..<min(tx + tw, region.x1) {
                            let mask = tile.isEmpty ? 0 : Int(byte(tile, ((y - ty) * tw + (x - tx)) * precision.bytes, precision, colour: false))
                            let d = ((y - region.y0) * region.width + (x - region.x0)) * 4 + 3
                            out[d] = UInt8((Int(out[d]) * mask + 127) / 255)
                        }
                    }
                }
            }
        }
    }

    /// XCF's RLE: each byte plane of the tile in turn, runs of one byte and runs of literal bytes.
    private static func unRLE(_ source: UnsafeBufferPointer<UInt8>, into tile: inout [UInt8], pixels: Int, bpp: Int) throws {
        var i = 0
        for plane in 0..<bpp {
            var n = 0
            while n < pixels {
                guard i < source.count else { throw OwnDecodeError.truncated }
                let op = Int(source[i])
                i += 1
                let count: Int, literal: Bool
                if op == 127 || op == 128 {
                    guard source.count - i >= 2 else { throw OwnDecodeError.truncated }
                    count = Int(source[i]) << 8 | Int(source[i + 1])
                    i += 2
                    literal = op == 128
                } else {
                    count = op < 127 ? op + 1 : 256 - op
                    literal = op > 128
                }
                guard n + count <= pixels else { throw OwnDecodeError.corrupt }
                if literal {
                    guard source.count - i >= count else { throw OwnDecodeError.truncated }
                    for k in 0..<count { tile[(n + k) * bpp + plane] = source[i + k] }
                    i += count
                } else {
                    guard i < source.count else { throw OwnDecodeError.truncated }
                    let value = source[i]
                    i += 1
                    for k in 0..<count { tile[(n + k) * bpp + plane] = value }
                }
                n += count
            }
        }
    }

    /// One big-endian component as 8-bit sRGB: integers scale, floats clamp to 0…1, and linear-light
    /// colour goes through the sRGB transfer function (alpha and masks don't).
    @inline(__always)
    private static func byte(_ tile: UnsafeBufferPointer<UInt8>, _ i: Int, _ precision: Precision, colour: Bool) -> UInt8 {
        if precision.bytes == 1, !precision.isLinear || !colour { return tile[i] }
        var bits: UInt64 = 0
        for k in 0..<precision.bytes { bits = bits << 8 | UInt64(tile[i + k]) }
        let value: Double
        switch (precision.bytes, precision.isFloat) {
        case (1, _): value = Double(bits) / 255
        case (2, false): value = Double(bits) / 65535
        case (4, false): value = Double(bits) / 4294967295
        case (2, true): value = half(Int(bits))
        case (4, true): value = Double(Float(bitPattern: UInt32(bits)))
        default: value = Double(bitPattern: bits)
        }
        let unit = value.isNaN ? 0 : min(max(value, 0), 1)
        return colour && precision.isLinear ? linearToSRGB[Int(unit * 65535 + 0.5)] : UInt8(unit * 255 + 0.5)
    }

    /// IEEE half by hand (sign, 5-bit exponent, 10-bit mantissa): `Float16` doesn't exist on Intel Macs.
    private static func half(_ bits: Int) -> Double {
        let sign: FloatingPointSign = bits & 0x8000 != 0 ? .minus : .plus
        let exponent = bits >> 10 & 0x1F, mantissa = Double(bits & 0x3FF)
        switch exponent {
        case 0: return Double(sign: sign, exponent: -24, significand: mantissa)  // subnormal
        case 31: return mantissa == 0 ? (sign == .minus ? -.infinity : .infinity) : .nan
        default: return Double(sign: sign, exponent: exponent - 15, significand: 1 + mantissa / 1024)
        }
    }

    /// Linear light 0…1 in 65,536 steps to 8-bit sRGB.
    private static let linearToSRGB: [UInt8] = (0...65535).map { i in
        let c = Double(i) / 65535
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(min(max(v, 0), 1) * 255 + 0.5)
    }
}
