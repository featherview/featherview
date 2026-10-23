import Foundation

/// Re-lays out a HEIF that ImageIO wrote the way other writers do (data before the meta box, a base offset,
/// iloc version 2 with 8-byte fields, 16-bit property indices), for `HEIFOrientation`'s tests.
enum HEIFLayout {
    struct Options {
        var mdatFirst = false, ilocVersion = 1, offsetSize = 4, baseSize = 0, useBase = false, wideIPMA = false
        /// Writes this as every base offset instead of the real one (a broken file).
        var baseOverride: Int?
    }

    struct Box { let type: String, start: Int, body: Int, end: Int }

    static func read(_ d: [UInt8], _ at: Int, _ size: Int) -> Int { d[at..<at + size].reduce(0) { $0 << 8 | Int($1) } }
    static func be(_ value: Int, _ size: Int) -> [UInt8] {
        (0..<size).map { UInt8(truncatingIfNeeded: value >> ((size - 1 - $0) * 8)) }
    }
    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { be(8 + payload.count, 4) + Array(type.utf8) + payload }

    static func boxes(_ d: [UInt8], _ from: Int, _ to: Int) -> [Box] {
        var result: [Box] = [], at = from
        while at + 8 <= to {
            var size = read(d, at, 4), body = at + 8
            if size == 1 { size = read(d, at + 8, 8); body = at + 16 } else if size == 0 { size = to - at }
            result.append(Box(type: String(decoding: d[at + 4..<at + 8], as: UTF8.self), start: at, body: body,
                              end: at + size))
            at += size
        }
        return result
    }

    /// The payload of the top-level `mdat`: what a lossless rewrite must leave alone.
    static func mdatPayload(_ data: Data) -> [UInt8] {
        let d = [UInt8](data)
        guard let mdat = boxes(d, 0, d.count).first(where: { $0.type == "mdat" }) else { return [] }
        return Array(d[mdat.body..<mdat.end])
    }

    typealias Item = (id: Int, method: Int, reference: Int, extents: [(offset: Int, length: Int)])

    /// Items' extents as iloc gives them (offsets relative to idat for method 1).
    static func items(_ d: [UInt8], _ iloc: Box) -> [Item] {
        let version = Int(d[iloc.body]), sizes = read(d, iloc.body + 4, 2)
        let (offsetSize, lengthSize, baseSize) = (sizes >> 12, sizes >> 8 & 15, sizes >> 4 & 15)
        let indexSize = version == 0 ? 0 : sizes & 15
        var at = iloc.body + 6
        func next(_ size: Int) -> Int { defer { at += size }; return size == 0 ? 0 : read(d, at, size) }
        var items: [Item] = []
        for _ in 0..<next(version < 2 ? 2 : 4) {
            let id = next(version < 2 ? 2 : 4), method = version > 0 ? next(2) & 15 : 0
            let reference = next(2), base = next(baseSize)
            let extents = (0..<next(2)).map { _ -> (offset: Int, length: Int) in
                _ = next(indexSize)
                return (base + next(offsetSize), next(lengthSize))
            }
            items.append((id, method, reference, extents))
        }
        return items
    }

    /// The Exif item's orientation tag, read straight from the file (ImageIO reports irot/imir instead).
    static func exifOrientation(_ data: Data) -> Int? {
        let d = [UInt8](data)
        guard let meta = boxes(d, 0, d.count).first(where: { $0.type == "meta" }) else { return nil }
        let children = boxes(d, meta.body + 4, meta.end)
        let iinf = children.first { $0.type == "iinf" }!
        let start = iinf.body + (d[iinf.body] == 0 ? 6 : 8)
        guard let exif = boxes(d, start, iinf.end).first(where: {
            d[$0.body] >= 2 && String(decoding: d[$0.body + (d[$0.body] == 2 ? 8 : 10)..<$0.body + (d[$0.body] == 2 ? 12 : 14)],
                                      as: UTF8.self) == "Exif"
        }) else { return nil }
        let id = read(d, exif.body + 4, d[exif.body] == 2 ? 2 : 4)
        let item = items(d, children.first { $0.type == "iloc" }!).first { $0.id == id }!
        let idat = children.first { $0.type == "idat" }?.body ?? 0
        let at = item.extents[0].offset + (item.method == 1 ? idat : 0)
        let tiff = at + 4 + read(d, at, 4)
        let little = d[tiff] == 0x49
        func value(_ at: Int, _ size: Int) -> Int {
            little ? d[at..<at + size].reversed().reduce(0) { $0 << 8 | Int($1) } : read(d, at, size)
        }
        let ifd = tiff + value(tiff + 4, 4)
        for n in 0..<value(ifd, 2) where value(ifd + 2 + n * 12, 2) == 0x0112 { return value(ifd + 2 + n * 12 + 8, 2) }
        return nil
    }

    static func relayout(_ data: Data, _ o: Options) -> Data {
        let d = [UInt8](data)
        let top = boxes(d, 0, d.count)
        let ftyp = top.first { $0.type == "ftyp" }!, meta = top.first { $0.type == "meta" }!
        let children = boxes(d, meta.body + 4, meta.end)
        let items = Self.items(d, children.first { $0.type == "iloc" }!)
        var blob: [UInt8] = [], placed: [Int: [(offset: Int, length: Int)]] = [:]
        for item in items where item.method == 0 {
            placed[item.id] = item.extents.map { extent in
                defer { blob += d[extent.offset..<extent.offset + extent.length] }
                return (blob.count, extent.length)
            }
        }

        func newILOC(_ dataStart: Int) -> [UInt8] {
            let v = o.ilocVersion, idSize = v < 2 ? 2 : 4
            var body: [UInt8] = [UInt8(v), 0, 0, 0] + be(o.offsetSize << 12 | 4 << 8 | o.baseSize << 4, 2)
                + be(items.count, idSize)
            for item in items {
                body += be(item.id, idSize) + (v > 0 ? be(item.method, 2) : []) + be(item.reference, 2)
                let extents = item.method == 0 ? placed[item.id]!.map { (dataStart + $0.offset, $0.length) } : item.extents
                let base = item.method == 0 && o.useBase ? (extents.first?.0 ?? 0) : 0
                body += be(o.baseOverride ?? base, o.baseSize) + be(extents.count, 2)
                for extent in extents { body += be(extent.0 - base, o.offsetSize) + be(extent.1, 4) }
            }
            return box("iloc", body)
        }
        func newIPRP(_ iprp: Box) -> [UInt8] {
            var parts: [UInt8] = []
            for child in boxes(d, iprp.body, iprp.end) {
                guard child.type == "ipma", o.wideIPMA, d[child.body + 3] & 1 == 0 else {
                    parts += d[child.start..<child.end]
                    continue
                }
                let idSize = d[child.body] == 0 ? 2 : 4
                var at = child.body + 8, body: [UInt8] = Array(d[child.body..<child.body + 3]) + [d[child.body + 3] | 1]
                    + d[child.body + 4..<child.body + 8]
                for _ in 0..<read(d, child.body + 4, 4) {
                    body += d[at..<at + idSize + 1]
                    let count = Int(d[at + idSize])
                    at += idSize + 1
                    for _ in 0..<count {
                        body += be(Int(d[at] & 0x7F) | (d[at] & 0x80 != 0 ? 0x8000 : 0), 2)
                        at += 1
                    }
                }
                parts += box("ipma", body)
            }
            return box("iprp", parts)
        }
        func newMeta(_ dataStart: Int) -> [UInt8] {
            var body = Array(d[meta.body..<meta.body + 4])
            for child in children {
                body += child.type == "iloc" ? newILOC(dataStart) : child.type == "iprp" ? newIPRP(child)
                    : Array(d[child.start..<child.end])
            }
            return box("meta", body)
        }
        let head = Array(d[ftyp.start..<ftyp.end])
        if o.mdatFirst { return Data(head + box("mdat", blob) + newMeta(head.count + 8)) }
        let metaSize = newMeta(0).count  // fixed-size fields: the size doesn't depend on the offsets
        return Data(head + newMeta(head.count + metaSize + 8) + box("mdat", blob))
    }
}
