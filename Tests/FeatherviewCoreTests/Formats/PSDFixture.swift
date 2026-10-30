import Compression
import Foundation

/// Builds PSD (version 1) and PSB (version 2) files in code: header, an optional ICC profile resource, an
/// optional version info resource (1057) with its "has real merged data" flag, an empty layer and mask section,
/// then the stored composite, raw or PackBits RLE. `makeLayered` writes a layer and mask section too.
enum PSDFixture {
    typealias Rect = (top: Int, left: Int, bottom: Int, right: Int)

    struct FixtureMask {
        var rect: Rect
        /// `width × height` of `rect`, one byte each.
        var pixels: [UInt8]
        var defaultColour: UInt8 = 0
        var disabled = false
    }

    /// One layer record as Photoshop stores it, bottom to top. `group` makes it a folder (open or closed,
    /// the group's top) or a divider (its bottom).
    struct FixtureLayer {
        enum Section: Int { case open = 1, closed = 2, divider = 3 }
        var name = "Layer"
        var rect: Rect = (0, 0, 0, 0)
        /// RGBA, `width × height` of `rect`.
        var pixels: [UInt8] = []
        var blend = "norm"
        var opacity: UInt8 = 255
        var clipped = false
        var hidden = false
        var mask: FixtureMask?
        /// 0 raw, 1 RLE, 2 zip, 3 zip with prediction.
        var compression = 0
        var group: Section?
        var blocks: [String: Data] = [:]
        /// Gray, red, green, blue: 4 source then 4 backdrop bytes each; nil writes the full ranges.
        var blendIf: [UInt8]?
        /// Channel bytes by channel ID, compression field included, in place of what `pixels` gives.
        var override: [Int: [UInt8]] = [:]
    }

    /// A white stored composite under a layer and mask section; `realComposite` nil leaves out resource 1057.
    static func makeLayered(width: Int, height: Int, layers: [FixtureLayer], realComposite: Bool? = false,
                            version: Int = 1) -> Data {
        func be(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        let long = version == 1 ? 4 : 8
        var bytes = Array("8BPS".utf8) + be(version, 2) + [UInt8](repeating: 0, count: 6)
        bytes += be(3, 2) + be(height, 4) + be(width, 4) + be(8, 2) + be(3, 2)
        bytes += be(0, 4)
        var resources: [UInt8] = []
        if let realComposite {
            resources += Array("8BIM".utf8) + be(1057, 2) + [0, 0] + be(5, 4) + be(1, 4) + [realComposite ? 1 : 0, 0]
        }
        bytes += be(resources.count, 4) + resources

        var records: [UInt8] = [], channelData: [UInt8] = []
        for layer in layers {
            let w = layer.rect.right - layer.rect.left, h = layer.rect.bottom - layer.rect.top
            var planes: [(id: Int, plane: [UInt8], w: Int, h: Int)] = [-1, 0, 1, 2].map { id in
                let plane = layer.pixels.isEmpty ? [] : (0..<w * h).map { layer.pixels[$0 * 4 + (id < 0 ? 3 : id)] }
                return (id, plane, w, h)
            }
            if let mask = layer.mask {
                planes.append((-2, mask.pixels, mask.rect.right - mask.rect.left, mask.rect.bottom - mask.rect.top))
            }
            records += be(layer.rect.top, 4) + be(layer.rect.left, 4) + be(layer.rect.bottom, 4) + be(layer.rect.right, 4)
            records += be(planes.count, 2)
            for p in planes {
                let data = layer.override[p.id] ?? channel(p.plane, width: p.w, height: p.h, compression: layer.compression, version: version)
                records += be(p.id, 2) + be(data.count, long)
                channelData += data
            }
            records += Array("8BIM".utf8) + Array(layer.blend.utf8) + [layer.opacity, layer.clipped ? 1 : 0, layer.hidden ? 2 : 0, 0]
            var extra: [UInt8] = []
            if let mask = layer.mask {
                extra += be(20, 4) + be(mask.rect.top, 4) + be(mask.rect.left, 4) + be(mask.rect.bottom, 4) + be(mask.rect.right, 4)
                extra += [mask.defaultColour, mask.disabled ? 2 : 0, 0, 0]
            } else {
                extra += be(0, 4)
            }
            let ranges = layer.blendIf ?? Array(repeating: [0, 0, 255, 255] as [UInt8], count: 8).flatMap { $0 }
            extra += be(ranges.count, 4) + ranges
            var name = [UInt8(layer.name.utf8.count)] + Array(layer.name.utf8)
            while name.count % 4 != 0 { name.append(0) }
            extra += name
            var blocks = layer.blocks
            if let group = layer.group { blocks["lsct"] = Data(be(group.rawValue, 4) + Array("8BIM".utf8) + Array(layer.blend.utf8)) }
            for (key, data) in blocks.sorted(by: { $0.key < $1.key }) {
                let longKey = version == 2 && ["LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD"].contains(key)
                extra += Array("8BIM".utf8) + Array(key.utf8) + be(data.count, longKey ? 8 : 4) + Array(data)
            }
            records += be(extra.count, 4) + extra
        }
        var info = be(layers.count, 2) + records + channelData
        if info.count % 2 == 1 { info.append(0) }
        let section = be(info.count, long) + info + be(0, 4)
        bytes += be(section.count, long) + section

        bytes += be(0, 2)
        bytes += [UInt8](repeating: 255, count: 3 * width * height)
        return Data(bytes)
    }

    /// One channel as stored: compression field, then raw, RLE (row byte counts, then PackBits rows) or zlib bytes.
    static func channel(_ plane: [UInt8], width: Int, height: Int, compression: Int, version: Int) -> [UInt8] {
        let field: [UInt8] = [0, UInt8(compression)]
        switch compression {
        case 1:
            let rows = (0..<height).map { packBits(Array(plane[$0 * width ..< ($0 + 1) * width])) }
            let counts = rows.flatMap { row in (0..<(version == 1 ? 2 : 4)).reversed().map { UInt8(truncatingIfNeeded: row.count >> ($0 * 8)) } }
            return field + counts + rows.flatMap { $0 }
        case 2, 3:
            var bytes = plane
            if compression == 3 {
                for y in 0..<height {
                    for x in stride(from: width - 1, to: 0, by: -1) { bytes[y * width + x] &-= bytes[y * width + x - 1] }
                }
            }
            return field + zlib(bytes)
        default:
            return field + plane
        }
    }

    /// RFC 1950: header, deflate, Adler-32.
    static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 64)
        let n = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = b << 16 | a
        return [0x78, 0x9C] + out.prefix(n) + [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: adler >> $0) }
    }

    static func make(width: Int, height: Int, pixels: [(UInt8, UInt8, UInt8)], version: Int = 1, compression: Int = 0,
                     icc: Data? = nil, realMerged: Bool? = nil, channels: Int = 3, depth: Int = 8, mode: Int = 3) -> Data {
        func be(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        var bytes = Array("8BPS".utf8) + be(version, 2) + [UInt8](repeating: 0, count: 6)
        bytes += be(channels, 2) + be(height, 4) + be(width, 4) + be(depth, 2) + be(mode, 2)
        bytes += be(0, 4)  // colour mode data
        var resources: [UInt8] = []
        if let icc {
            resources += Array("8BIM".utf8) + be(1039, 2) + [0, 0] + be(icc.count, 4) + Array(icc)
            if icc.count % 2 == 1 { resources.append(0) }
        }
        if let realMerged {
            resources += Array("8BIM".utf8) + be(1057, 2) + [0, 0] + be(5, 4) + be(1, 4) + [realMerged ? 1 : 0, 0]
        }
        bytes += be(resources.count, 4) + resources
        bytes += be(0, version == 1 ? 4 : 8)  // layer and mask info
        bytes += be(compression, 2)

        // One row of one channel, as stored: 1 byte per sample at depth 8, the sample twice at depth 16.
        func row(_ c: Int, _ y: Int) -> [UInt8] {
            (0..<width).flatMap { x -> [UInt8] in
                let p = pixels[y * width + x]
                let v = c == 0 ? p.0 : c == 1 ? p.1 : c == 2 ? p.2 : 255
                return [UInt8](repeating: v, count: depth / 8)
            }
        }
        let rows = (0..<channels).flatMap { c in (0..<height).map { row(c, $0) } }
        if compression == 1 {
            let packed = rows.map(packBits)
            for p in packed { bytes += be(p.count, version == 1 ? 2 : 4) }
            for p in packed { bytes += p }
        } else {
            for r in rows { bytes += r }
        }
        return Data(bytes)
    }

    /// PackBits: repeat runs of 3 or more equal bytes, literal runs for the rest, at most 128 per run.
    static func packBits(_ row: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [], i = 0
        while i < row.count {
            var run = 1
            while i + run < row.count, run < 128, row[i + run] == row[i] { run += 1 }
            if run >= 3 {
                out += [UInt8(bitPattern: Int8(1 - run)), row[i]]
                i += run
                continue
            }
            var end = i
            while end < row.count, end - i < 128 {
                if end + 2 < row.count, row[end] == row[end + 1], row[end] == row[end + 2] { break }
                end += 1
            }
            out.append(UInt8(end - i - 1))
            out += row[i..<end]
            i = end
        }
        return out
    }
}
