import Foundation

/// Sets a HEIF file's orientation by rewriting only its item properties (`irot`/`imir`), never the image data.
/// ImageIO's own lossless rewrite refuses a HEIC with an ISO gain map ("modifyHEIC failed"). This writes what
/// ImageIO's encoder writes: the transform goes on the primary item and the items that belong to it
/// (thumbnail, alpha, Apple gain map) via `thmb`/`auxl`; the `tmap` item and its gain map keep their own,
/// and the `tmap` takes the displayed size (else ImageIO no longer finds the gain map).
enum HEIFOrientation {
    private struct Malformed: Error {}

    /// EXIF orientation as HEIF's anticlockwise quarter turns, then the mirror axis (0 = left–right) if any.
    static let transforms: [Int: (angle: UInt8, axis: UInt8?)] = [
        1: (0, nil), 2: (0, 1), 3: (2, nil), 4: (0, 0), 5: (1, 0), 6: (3, nil), 7: (1, 1), 8: (1, nil),
    ]

    /// `file` with EXIF orientation `orientation`, or nil for a layout this doesn't handle.
    static func setting(_ orientation: Int, in file: Data) -> Data? {
        guard transforms[orientation] != nil else { return nil }
        var bytes = [UInt8](file)
        guard (try? apply(orientation, to: &bytes)) != nil else { return nil }
        return Data(bytes)
    }

    private struct Box {
        let type: String, start: Int, body: Int, end: Int
    }

    private static func apply(_ orientation: Int, to d: inout [UInt8]) throws {
        guard let transform = transforms[orientation] else { throw Malformed() }
        func read(_ at: Int, _ size: Int) throws -> Int {
            guard at >= 0, size >= 0, size <= 8, size <= d.count - at else { throw Malformed() }
            return d[at..<at + size].reduce(0) { $0 << 8 | Int($1) }
        }
        /// A size or offset: within the file, so sums of two never overflow.
        func position(_ at: Int, _ size: Int) throws -> Int {
            let value = try read(at, size)
            guard value >= 0, value <= d.count else { throw Malformed() }
            return value
        }
        func boxes(_ from: Int, _ to: Int) throws -> [Box] {
            var result: [Box] = [], at = from
            while at + 8 <= to {
                var size = try read(at, 4), body = at + 8
                if size == 1 { size = try position(at + 8, 8); body = at + 16 } else if size == 0 { size = to - at }
                guard size >= body - at, size <= to - at else { throw Malformed() }
                result.append(Box(type: String(decoding: d[at + 4..<at + 8], as: UTF8.self), start: at, body: body,
                                  end: at + size))
                at += size
            }
            return result
        }
        func only(_ type: String, _ list: [Box]) throws -> Box {
            let found = list.filter { $0.type == type }
            guard found.count == 1 else { throw Malformed() }
            return found[0]
        }

        let top = try boxes(0, d.count)
        // A sequence's moov holds chunk offsets this doesn't move.
        guard let meta = top.first(where: { $0.type == "meta" }), !top.contains(where: { $0.type == "moov" })
        else { throw Malformed() }
        let children = try boxes(meta.body + 4, meta.end)  // meta is a full box: version and flags first
        let pitm = try only("pitm", children), iprp = try only("iprp", children), iloc = try only("iloc", children)
        let primary = try read(pitm.body + 4, try read(pitm.body, 1) == 0 ? 2 : 4)

        // The primary and the items that point at it as its thumbnail or auxiliary image take the transform;
        // items derived from it (the tmap) take its displayed size.
        var targets: Set<Int> = [primary], derived: Set<Int> = []
        if let iref = children.first(where: { $0.type == "iref" }) {
            let idSize = try read(iref.body, 1) == 0 ? 2 : 4
            for reference in try boxes(iref.body + 4, iref.end) where ["thmb", "auxl", "dimg"].contains(reference.type) {
                let from = try read(reference.body, idSize), count = try read(reference.body + idSize, 2)
                let to = try (0..<count).map { try read(reference.body + idSize + 2 + $0 * idSize, idSize) }
                guard to.contains(primary) else { continue }
                if reference.type == "dimg" { derived.insert(from) } else { targets.insert(from) }
            }
        }

        let iprpChildren = try boxes(iprp.body, iprp.end)
        let ipco = try only("ipco", iprpChildren), ipma = try only("ipma", iprpChildren)
        let existing = try boxes(ipco.body, ipco.end)
        var types = existing.map(\.type)  // property index n is types[n - 1]

        let version = try read(ipma.body, 1), flags = try read(ipma.body + 1, 3)
        let idSize = version == 0 ? 2 : 4, wide = flags & 1 != 0
        var entries: [(item: Int, associations: [(essential: Bool, index: Int)])] = []
        var at = ipma.body + 8
        for _ in 0..<(try read(ipma.body + 4, 4)) {
            let item = try read(at, idSize)
            at += idSize
            let count = try read(at, 1)
            at += 1
            var associations: [(essential: Bool, index: Int)] = []
            for _ in 0..<count {
                let value = try read(at, wide ? 2 : 1)
                at += wide ? 2 : 1
                let high = wide ? 0x8000 : 0x80
                associations.append((value & high != 0, value & (high - 1)))
            }
            entries.append((item, associations))
        }
        guard at == ipma.end, let primaryEntry = entries.first(where: { $0.item == primary }),
              let ispe = primaryEntry.associations.first(where: { types[safe: $0.index - 1] == "ispe" })
        else { throw Malformed() }
        let stored = existing[ispe.index - 1].body + 4  // ispe: version and flags, width, height
        let (width, height) = (try read(stored, 4), try read(stored + 4, 4))

        // Properties: reuse one with the wanted value, else append it.
        var ipcoBytes = Array(d[ipco.start..<ipco.end])
        func property(_ type: String, _ payload: [UInt8]) -> Int {
            if let index = existing.indices.first(where: {
                existing[$0].type == type && Array(d[existing[$0].body..<existing[$0].end]) == payload
            }) { return index + 1 }
            ipcoBytes += be(8 + payload.count, 4) + Array(type.utf8) + payload
            types.append(type)
            return types.count
        }
        var turn = [property("irot", [transform.angle])]
        if let axis = transform.axis { turn.append(property("imir", [axis])) }
        let displayed = transform.angle % 2 == 1 ? be(height, 4) + be(width, 4) : be(width, 4) + be(height, 4)
        let displayedSize = property("ispe", [0, 0, 0, 0] + displayed)
        ipcoBytes.replaceSubrange(0..<4, with: be(ipcoBytes.count, 4))

        // Transforms come last, irot before imir.
        for n in entries.indices {
            if targets.contains(entries[n].item) {
                entries[n].associations.removeAll { ["irot", "imir"].contains(types[safe: $0.index - 1]) }
                entries[n].associations += turn.map { (true, $0) }
            } else if derived.contains(entries[n].item) {
                for a in entries[n].associations.indices where types[safe: entries[n].associations[a].index - 1] == "ispe" {
                    entries[n].associations[a].index = displayedSize
                }
            }
        }
        let wideOut = wide || types.count > 127
        var ipmaBytes: [UInt8] = [0, 0, 0, 0] + Array("ipma".utf8) + [UInt8(version)] + be(flags | (wideOut ? 1 : 0), 3)
            + be(entries.count, 4)
        for entry in entries {
            guard entry.associations.count <= 255 else { throw Malformed() }
            ipmaBytes += be(entry.item, idSize) + [UInt8(entry.associations.count)]
            for association in entry.associations {
                ipmaBytes += wideOut ? be(association.index | (association.essential ? 0x8000 : 0), 2)
                    : [UInt8(association.index | (association.essential ? 0x80 : 0))]
            }
        }
        ipmaBytes.replaceSubrange(0..<4, with: be(ipmaBytes.count, 4))

        var iprpBytes: [UInt8] = [0, 0, 0, 0] + Array("iprp".utf8)
        for child in iprpChildren {
            iprpBytes += child.type == "ipco" ? ipcoBytes : child.type == "ipma" ? ipmaBytes : Array(d[child.start..<child.end])
        }
        iprpBytes.replaceSubrange(0..<4, with: be(iprpBytes.count, 4))
        let delta = iprpBytes.count - (iprp.end - iprp.start)

        // Items' data: (position of the base offset, base, positions of the extent offsets, offsets, lengths).
        let ilocVersion = try read(iloc.body, 1), sizes = try read(iloc.body + 4, 2)
        let offsetSize = sizes >> 12, lengthSize = sizes >> 8 & 15, baseSize = sizes >> 4 & 15
        let indexSize = ilocVersion == 0 ? 0 : sizes & 15, itemIDSize = ilocVersion < 2 ? 2 : 4
        var items: [Int: (method: Int, reference: Int, basePosition: Int, base: Int,
                          extents: [(position: Int, offset: Int, length: Int)])] = [:]
        let itemCount = try read(iloc.body + 6, itemIDSize)
        at = iloc.body + 6 + itemIDSize
        for _ in 0..<itemCount {
            let id = try read(at, itemIDSize)
            at += itemIDSize
            var method = 0
            if ilocVersion > 0 { method = try read(at, 2) & 15; at += 2 }
            let reference = try read(at, 2), basePosition = at + 2
            let base = try position(basePosition, baseSize)
            at = basePosition + baseSize
            let count = try read(at, 2)
            at += 2
            var extents: [(position: Int, offset: Int, length: Int)] = []
            for _ in 0..<count {
                at += indexSize
                extents.append((at, try position(at, offsetSize), try position(at + offsetSize, lengthSize)))
                at += offsetSize + lengthSize
            }
            items[id] = (method, reference, basePosition, base, extents)
        }
        guard at <= iloc.end else { throw Malformed() }

        // Data stored after the meta box moves by delta: shift the absolute offsets in iloc (same size, in place).
        func shift(_ at: Int, _ size: Int) throws {
            let moved = try read(at, size) + delta
            guard size > 0, moved >= 0, size == 8 || moved < 1 << (size * 8) else { throw Malformed() }
            d.replaceSubrange(at..<at + size, with: be(moved, size))
        }
        if delta != 0 {
            for item in items.values where item.method == 0 && item.reference == 0 {  // else in idat or another file
                let absolute = item.extents.map { item.base + $0.offset }
                if absolute.allSatisfy({ $0 < meta.start }) { continue }
                guard absolute.allSatisfy({ $0 >= meta.end }) else { throw Malformed() }
                if baseSize > 0 && item.base >= meta.end { try shift(item.basePosition, baseSize) }
                else { for extent in item.extents { try shift(extent.position, offsetSize) } }
            }
        }

        // The Exif item's orientation tag follows, as ImageIO's own rewrite keeps it, for tools that read it.
        // Same size, in place; a missing or unreadable tag is left alone.
        if let iinf = children.first(where: { $0.type == "iinf" }) {
            let idat = children.first { $0.type == "idat" }?.body
            let start = iinf.body + (try read(iinf.body, 1) == 0 ? 6 : 8)
            for entry in try boxes(start, iinf.end) where entry.type == "infe" {
                let version = try read(entry.body, 1)
                guard version >= 2 else { continue }
                let idSize = version == 2 ? 2 : 4
                guard try read(entry.body + 4 + idSize + 2, 4) == 0x4578_6966,  // "Exif"
                      let item = items[try read(entry.body + 4, idSize)], item.reference == 0,
                      item.extents.count == 1, item.method == 0 || (item.method == 1 && idat != nil)
                else { continue }
                let begin = (item.method == 1 ? idat! : 0) + item.base + item.extents[0].offset
                try? setExifOrientation(orientation, in: &d, begin..<begin + item.extents[0].length)
            }
        }

        d.replaceSubrange(iprp.start..<iprp.end, with: iprpBytes)
        let metaSize = meta.end - meta.start + delta
        if meta.body - meta.start == 16 { d.replaceSubrange(meta.start + 8..<meta.start + 16, with: be(metaSize, 8)) }
        else if metaSize < 1 << 32 { d.replaceSubrange(meta.start..<meta.start + 4, with: be(metaSize, 4)) }
        else { throw Malformed() }
    }

    /// Overwrites tag 0x0112 in IFD0 of the Exif item in `range` (4-byte header offset, then TIFF).
    private static func setExifOrientation(_ orientation: Int, in d: inout [UInt8], _ range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound <= d.count else { throw Malformed() }
        func value(_ at: Int, _ size: Int, little: Bool) throws -> Int {
            guard at >= range.lowerBound, size <= range.upperBound - at else { throw Malformed() }
            let bytes = d[at..<at + size]
            return (little ? bytes.reversed() : Array(bytes)).reduce(0) { $0 << 8 | Int($1) }
        }
        let tiff = try range.lowerBound + 4 + value(range.lowerBound, 4, little: false)
        guard tiff + 2 <= range.upperBound else { throw Malformed() }
        let little = d[tiff] == 0x49 && d[tiff + 1] == 0x49
        guard little || (d[tiff] == 0x4D && d[tiff + 1] == 0x4D) else { throw Malformed() }
        let ifd = try tiff + value(tiff + 4, 4, little: little)
        for n in 0..<(try value(ifd, 2, little: little)) {
            let entry = ifd + 2 + n * 12
            guard try value(entry, 2, little: little) == 0x0112, try value(entry + 2, 2, little: little) == 3,
                  try value(entry + 8, 2, little: little) != orientation else { continue }  // SHORT
            let bytes = be(orientation, 2)
            d.replaceSubrange(entry + 8..<entry + 10, with: little ? bytes.reversed() : bytes)
        }
    }

    private static func be(_ value: Int, _ size: Int) -> [UInt8] {
        (0..<size).map { UInt8(truncatingIfNeeded: value >> ((size - 1 - $0) * 8)) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
