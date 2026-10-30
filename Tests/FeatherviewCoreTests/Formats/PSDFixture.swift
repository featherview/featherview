import Foundation

/// Builds PSD (version 1) and PSB (version 2) files in code: header, an optional ICC profile resource, an
/// optional version info resource (1057) with its "has real merged data" flag, an empty layer and mask section,
/// then the stored composite, raw or PackBits RLE.
enum PSDFixture {
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
