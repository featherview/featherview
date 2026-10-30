import Compression
import Foundation

/// Builds TIFF and BigTIFF files in code: header, the pixel data in strips or tiles (raw, LZW or Deflate,
/// optionally with horizontal differencing), an optional ICC profile, then the IFD(s) at the end.
enum TIFFFixture {
    typealias RGB = (UInt8, UInt8, UInt8)

    static func make(width: Int, height: Int, pixels: [RGB], bigEndian: Bool = false, bigTIFF: Bool = false,
                     compression: Int = 1, predictor: Int = 1, rowsPerStrip: Int? = nil, tile: (Int, Int)? = nil,
                     icc: Data? = nil, samples: Int = 3, bits: Int = 8, photometric: Int = 2, planar: Int = 1,
                     orientation: Int? = nil, pages: Int = 1, paddedLastStrip: Bool = false) -> Data {
        let bytesPerSample = bits / 8
        func sample(_ x: Int, _ y: Int, _ s: Int) -> UInt8 {
            guard x < width, y < height else { return 0 }  // tiles are padded past the picture's edges
            let p = pixels[y * width + x]
            return s == 0 ? p.0 : s == 1 ? p.1 : s == 2 ? p.2 : 255
        }
        let (bw, bh) = tile ?? (width, rowsPerStrip ?? height)
        let planes = planar == 2 ? (0..<samples).map { [$0] } : [Array(0..<samples)]
        var blocks: [[UInt8]] = []
        for plane in planes {
            for ty in 0 ..< (height + bh - 1) / bh {
                for tx in 0 ..< (width + bw - 1) / bw {
                    // Some writers store the last strip full-size too, its rows past the picture zero.
                    let rows = tile == nil && !paddedLastStrip ? min(bh, height - ty * bh) : bh
                    var raw: [UInt8] = []
                    for y in 0..<rows {
                        var row: [UInt8] = []
                        for x in 0..<bw {
                            for s in plane { row += [UInt8](repeating: sample(tx * bw + x, ty * bh + y, s), count: bytesPerSample) }
                        }
                        if predictor == 2 { difference(&row, step: plane.count * bytesPerSample) }
                        raw += row
                    }
                    blocks.append(encode(raw, compression: compression))
                }
            }
        }
        return assemble(width: width, height: height, stored: blocks, index: Array(blocks.indices), bigEndian: bigEndian,
                        bigTIFF: bigTIFF, compression: compression, predictor: predictor, rowsPerStrip: rowsPerStrip,
                        tile: tile, icc: icc, samples: samples, bits: bits, photometric: photometric, planar: planar,
                        orientation: orientation, pages: pages)
    }

    /// A Deflate file of `width` × `height` whose strip offsets all point at one compressed strip of `rows` rows
    /// of `pixels` (`width` × `rows`), so a picture of hundreds of megapixels stays a few KB.
    static func makeRepeatedStrip(width: Int, height: Int, rows: Int, pixels: [RGB]) -> Data {
        let raw = pixels.flatMap { [$0.0, $0.1, $0.2] }
        return assemble(width: width, height: height, stored: [encode(raw, compression: 8)],
                        index: [Int](repeating: 0, count: (height + rows - 1) / rows), bigEndian: false, bigTIFF: false,
                        compression: 8, predictor: 1, rowsPerStrip: rows, tile: nil, icc: nil, samples: 3, bits: 8,
                        photometric: 2, planar: 1, orientation: nil, pages: 1)
    }

    /// Horizontal differencing (Predictor 2): each byte minus the one `step` bytes before it.
    static func difference(_ row: inout [UInt8], step: Int) {
        for i in stride(from: row.count - 1, through: step, by: -1) { row[i] &-= row[i - step] }
    }

    static func encode(_ raw: [UInt8], compression: Int) -> [UInt8] {
        switch compression {
        case 5: lzw(raw)
        case 8, 32946: InflateTests.zlib(raw)
        default: raw
        }
    }

    /// TIFF LZW: MSB-first codes of 9 to 12 bits, Clear (256) at the start and when the table reaches 4094,
    /// EOI (257) at the end, each width change one code early ("early change", as libtiff writes it).
    static func lzw(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [], acc: UInt64 = 0, bitCount = 0, width = 9, next = 258
        var table: [Int: Int] = [:]
        func put(_ code: Int) {
            acc = acc << UInt64(width) | UInt64(code)
            bitCount += width
            while bitCount >= 8 {
                bitCount -= 8
                out.append(UInt8(truncatingIfNeeded: acc >> UInt64(bitCount)))
            }
        }
        func added() {
            next += 1
            if next == 4094 {
                put(256)
                table = [:]
                next = 258
                width = 9
            } else if next == 1 << width {
                width += 1
            }
        }
        put(256)
        var prefix: Int?
        for byte in input {
            guard let p = prefix else { prefix = Int(byte); continue }
            if let code = table[p << 8 | Int(byte)] { prefix = code; continue }
            put(p)
            table[p << 8 | Int(byte)] = next
            added()
            prefix = Int(byte)
        }
        if let prefix { put(prefix); added() }
        put(257)
        if bitCount > 0 { out.append(UInt8(truncatingIfNeeded: acc << UInt64(8 - bitCount))) }
        return out
    }

    /// The file: header, `stored` blocks, the ICC profile, then `pages` copies of the IFD. Block `i` of the
    /// IFD's offsets is `stored[index[i]]`.
    private static func assemble(width: Int, height: Int, stored: [[UInt8]], index: [Int], bigEndian: Bool, bigTIFF: Bool,
                                 compression: Int, predictor: Int, rowsPerStrip: Int?, tile: (Int, Int)?, icc: Data?,
                                 samples: Int, bits: Int, photometric: Int, planar: Int, orientation: Int?, pages: Int) -> Data {
        func uint(_ value: Int, _ size: Int) -> [UInt8] {
            let little = (0..<size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
            return bigEndian ? little.reversed() : little
        }
        let headerSize = bigTIFF ? 16 : 8, offsetSize = bigTIFF ? 8 : 4, offsetType = bigTIFF ? 16 : 4
        var body = [UInt8](repeating: 0, count: headerSize)
        var storedAt: [Int] = []
        for block in stored {
            storedAt.append(body.count)
            body += block
            if body.count % 2 == 1 { body.append(0) }
        }

        var entries: [(tag: Int, type: Int, count: Int, bytes: [UInt8])] = []
        func add(_ tag: Int, _ type: Int, _ values: [Int]) {
            let size = [3: 2, 4: 4, 16: 8][type]!
            entries.append((tag, type, values.count, values.flatMap { uint($0, size) }))
        }
        let offsets = index.map { storedAt[$0] }, counts = index.map { stored[$0].count }
        add(256, 4, [width])
        add(257, 4, [height])
        add(258, 3, [Int](repeating: bits, count: samples))
        add(259, 3, [compression])
        add(262, 3, [photometric])
        if tile == nil { add(273, offsetType, offsets) }
        if let orientation { add(274, 3, [orientation]) }
        add(277, 3, [samples])
        if tile == nil {
            if let rowsPerStrip { add(278, 4, [rowsPerStrip]) }
            add(279, offsetType, counts)
        }
        add(284, 3, [planar])
        if predictor != 1 { add(317, 3, [predictor]) }
        if let tile {
            add(322, 4, [tile.0])
            add(323, 4, [tile.1])
            add(324, offsetType, offsets)
            add(325, offsetType, counts)
        }
        if samples > 3 { add(338, 3, [2]) }
        if let icc { entries.append((34675, 7, icc.count, Array(icc))) }

        func ifd(at offset: Int, next: Int) -> [UInt8] {
            let countSize = bigTIFF ? 8 : 2, entrySize = bigTIFF ? 20 : 12, inline = offsetSize
            var head = uint(entries.count, countSize), extra: [UInt8] = []
            let extraStart = offset + countSize + entries.count * entrySize + offsetSize
            for entry in entries {
                head += uint(entry.tag, 2) + uint(entry.type, 2) + uint(entry.count, offsetSize)
                if entry.bytes.count <= inline {
                    head += entry.bytes + [UInt8](repeating: 0, count: inline - entry.bytes.count)
                } else {
                    head += uint(extraStart + extra.count, offsetSize)
                    extra += entry.bytes
                    if extra.count % 2 == 1 { extra.append(0) }
                }
            }
            return head + uint(next, offsetSize) + extra
        }
        let first = body.count, ifdSize = ifd(at: 0, next: 0).count
        for page in 0..<pages {
            let at = first + page * ifdSize
            body += ifd(at: at, next: page + 1 < pages ? at + ifdSize : 0)
        }
        let header = Array((bigEndian ? "MM" : "II").utf8)
            + (bigTIFF ? uint(43, 2) + uint(8, 2) + uint(0, 2) + uint(first, 8) : uint(42, 2) + uint(first, 4))
        body.replaceSubrange(0..<headerSize, with: header)
        return Data(body)
    }
}
