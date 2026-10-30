import CoreGraphics
import Foundation
import os

/// The picture of an 8-bit chunky RGB TIFF or BigTIFF (raw, LZW or Deflate, strips or tiles), read straight
/// from the file: only the blocks a decode needs, in parallel bands, area-averaged to the size asked for.
/// Huge TIFFs open in a fraction of ImageIO's time and memory this way. Every other TIFF is left to ImageIO.
// shortcut: planar (PlanarConfiguration 2), 16-bit and alpha TIFFs go through ImageIO, read them here if huge ones turn up.
public struct TIFFRaster: RegionReader {
    public let width: Int
    public let height: Int
    /// Tag 34675's bytes, nil without one.
    public let icc: Data?

    private let url: URL
    private let compression: Int
    private let predictor: Bool
    private let tiled: Bool
    /// Strips: the picture's width and RowsPerStrip; tiles: the tile's size.
    private let blockWidth: Int
    private let blockHeight: Int
    /// Each block's file offset and stored byte count, block row by block row.
    private let offsets: [Int]
    private let counts: [Int]

    /// Reads only the header and the first IFD's tags it needs. Nil unless the file is a single-image 8-bit,
    /// 3-sample, chunky RGB TIFF or BigTIFF, upright, raw, LZW or Deflate (predictor none or horizontal), whose
    /// strips or tiles all lie inside the file.
    public init?(url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        let fileSize = Int(info.st_size)
        // Bounded by the file's size, so a damaged length never asks for a huge buffer.
        func bytes(_ offset: Int, _ count: Int) -> [UInt8]? {
            guard offset >= 0, count >= 0, offset <= fileSize - count else { return nil }
            return try? FileRead.bytes(fd, offset, count)
        }
        guard let head = bytes(0, 8), head[0] == head[1], head[0] == UInt8(ascii: "I") || head[0] == UInt8(ascii: "M")
        else { return nil }
        let little = head[0] == UInt8(ascii: "I")
        // Values past Int.max come out negative, which every bound below rejects.
        func int(_ b: ArraySlice<UInt8>) -> Int {
            Int(truncatingIfNeeded: (little ? b.reversed() : Array(b)).reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        }
        let magic = int(head[2..<4]), big = magic == 43
        guard magic == 42 || big else { return nil }
        var ifd = int(head[4..<8])
        if big {
            guard int(head[4..<6]) == 8, int(head[6..<8]) == 0, let first = bytes(8, 8) else { return nil }
            ifd = int(first[...])
        }
        let countSize = big ? 8 : 2, entrySize = big ? 20 : 12, fieldSize = big ? 8 : 4
        guard let countBytes = bytes(ifd, countSize) else { return nil }
        let n = int(countBytes[...])
        guard n > 0, n <= fileSize / entrySize, let entries = bytes(ifd + countSize, n * entrySize),
              let next = bytes(ifd + countSize + n * entrySize, fieldSize), int(next[...]) == 0 else { return nil }

        // Only the tags read here: others (a Photoshop layer blob, XMP) can be large and are never read.
        let wanted: Set<Int> = [256, 257, 258, 259, 262, 266, 273, 274, 277, 278, 279, 284, 317, 322, 323, 324, 325, 339]
        var tags: [Int: [Int]] = [:]
        var icc: Data?
        var seen: Set<Int> = []
        for e in 0..<n {
            let at = e * entrySize
            let tag = int(entries[at ..< at + 2]), type = int(entries[at + 2 ..< at + 4])
            guard tag != 338 else { return nil }  // ExtraSamples: alpha or more
            guard tag == 34675 || wanted.contains(tag) else { continue }
            // A repeated tag: no writer stores one, and each copy could ask for a file-sized array to be parsed.
            guard seen.insert(tag).inserted else { return nil }
            // BYTE, SHORT, LONG and LONG8 for numbers; BYTE or UNDEFINED for the profile.
            guard let size = (tag == 34675 ? [1: 1, 7: 1] : [1: 1, 3: 2, 4: 4, 16: 8])[type] else { return nil }
            let count = int(entries[at + 4 ..< at + 4 + fieldSize])
            guard count >= 0, count <= fileSize else { return nil }
            let field = entries[at + 4 + fieldSize ..< at + entrySize]
            let value: ArraySlice<UInt8>
            if count * size <= fieldSize {
                value = field.prefix(count * size)
            } else {
                guard let stored = bytes(int(field), count * size) else { return nil }
                value = stored[...]
            }
            if tag == 34675 {
                icc = Data(value)
            } else {
                tags[tag] = stride(from: value.startIndex, to: value.endIndex, by: size).map { int(value[$0 ..< $0 + size]) }
            }
        }
        /// A single-valued tag, `absent` when it isn't there, nil when it has several values.
        func one(_ tag: Int, _ absent: Int? = nil) -> Int? {
            guard let values = tags[tag] else { return absent }
            return values.count == 1 ? values[0] : nil
        }
        // At most 300,000 per side, which keeps decode's 32-bit row sums from overflowing.
        guard let width = one(256), let height = one(257), (1...300_000).contains(width), (1...300_000).contains(height),
              tags[258] == [8, 8, 8], one(277) == 3, one(262) == 2, one(284, 1) == 1, one(266, 1) == 1, one(274, 1) == 1,
              tags[339].map({ $0.allSatisfy { $0 == 1 } }) ?? true,
              let compression = one(259, 1), [1, 5, 8, 32946].contains(compression),
              let predictor = one(317, 1), predictor == 1 || predictor == 2
        else { return nil }

        let tiled = tags[322] != nil
        let blockWidth: Int, blockHeight: Int, offsets: [Int], counts: [Int]
        if tiled {
            guard let tw = one(322), let th = one(323), (1...300_000).contains(tw), (1...300_000).contains(th),
                  tags[273] == nil, let o = tags[324], let c = tags[325],
                  o.count == ((width + tw - 1) / tw) * ((height + th - 1) / th), c.count == o.count else { return nil }
            (blockWidth, blockHeight, offsets, counts) = (tw, th, o, c)
        } else {
            guard let rows = one(278, height), rows >= 1, tags[324] == nil, let o = tags[273], let c = tags[279],
                  o.count == (height + min(rows, height) - 1) / min(rows, height), c.count == o.count else { return nil }
            (blockWidth, blockHeight, offsets, counts) = (width, min(rows, height), o, c)
        }
        // shortcut: a block over 16 MB decoded (one strip for the whole picture, huge tiles) goes to ImageIO, since every band decoding at once holds one; read such raw strips row by row if they turn up.
        guard blockWidth * blockHeight * 3 <= 16 << 20,
              zip(offsets, counts).allSatisfy({ $0 >= 0 && $1 >= 0 && $0 <= fileSize - $1 }) else { return nil }

        self.url = url
        self.width = width
        self.height = height
        self.icc = icc
        self.compression = compression
        self.predictor = predictor == 2
        self.tiled = tiled
        self.blockWidth = blockWidth
        self.blockHeight = blockHeight
        self.offsets = offsets
        self.counts = counts
    }

    /// How many of `bands` bands decode at once, each holding `bytesPerBand`: as many as fit in 256 MB, at least one.
    static func lanes(bands: Int, bytesPerBand: Int) -> Int {
        max(1, min(bands, (256 << 20) / max(1, bytesPerBand)))
    }

    /// See `RegionReader`; a block whose data decodes short throws too. A block stored longer (a padded last
    /// strip) is read up to its size, and one of byte count 0 (a sparse file) is zero, as ImageIO reads them.
    public func decode(region: CGRect?, size: PixelSize) throws -> CGImage {
        let (x0, y0, rw, rh, ow, oh) = try bounds(region, size: size)
        let columns = (0...ow).map { x0 + $0 * rw / ow }, rows = (0...oh).map { y0 + $0 * rh / oh }
        let across = (width + blockWidth - 1) / blockWidth
        let bx0 = x0 / blockWidth, bx1 = (x0 + rw - 1) / blockWidth
        // Bands of `k` output rows whose source rows span at least one block row and about 4 MB of decoded rows:
        // a block that two bands share is decoded by each, and larger bands share fewer.
        let sourceRows = max(blockHeight, (4 << 20) / ((bx1 - bx0 + 1) * blockWidth * 3))
        let k = min(oh, max(1, (sourceRows * oh + rh - 1) / rh))

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw OwnDecodeError.corrupt }
        defer { close(fd) }

        // Each band writes only its own output rows.
        nonisolated(unsafe) let output = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: ow * 4 * oh)
        let failed = OSAllocatedUnfairLock(initialState: false)
        let (height, blockWidth, blockHeight, tiled) = (height, blockWidth, blockHeight, tiled)
        let bands = (oh + k - 1) / k
        // A band holds its block, its compressed bytes and its sums: bounded, so a decode never takes gigabytes.
        let lanes = Self.lanes(bands: bands, bytesPerBand: blockWidth * blockHeight * 3 + (counts.max() ?? 0) + k * ow * 24)
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            for band in stride(from: lane, to: bands, by: lanes) {
                let oy0 = band * k, oy1 = min(oy0 + k, oh), s0 = rows[oy0], s1 = rows[oy1]
                let sums = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: (oy1 - oy0) * ow * 3)
                sums.initialize(repeating: 0)
                defer { sums.deallocate() }
                let block = UnsafeMutablePointer<UInt8>.allocate(capacity: blockWidth * blockHeight * 3)
                defer { block.deallocate() }
                // Compressed bytes land in one buffer per band: a fresh one per block costs page faults on every block.
                var packed: [UInt8] = []
                do {
                    try columns.withUnsafeBufferPointer { columns in
                        for by in s0 / blockHeight ... (s1 - 1) / blockHeight {
                            let top = by * blockHeight, ra = max(s0, top), rb = min(s1, top + blockHeight)
                            // Tiles are stored full-size at the edges; the last strip is shorter.
                            let stored = tiled ? blockHeight : min(blockHeight, height - top)
                            for bx in bx0...bx1 {
                                let left = bx * blockWidth, xa = max(x0, left), xb = min(x0 + rw, left + blockWidth)
                                // Up to the region's last column in the last row used: the rest of a strip is never looked at.
                                try decodeBlock(by * across + bx, rows: stored, needed: ((rb - top - 1) * blockWidth + xb - left) * 3,
                                                fd: fd, packed: &packed, into: block)
                                if predictor {
                                    for r in ra..<rb {
                                        // Three running sums in registers, not each byte read back from the one before.
                                        var p = block + (r - top) * blockWidth * 3
                                        var (red, green, blue) = (p[0], p[1], p[2])
                                        for _ in 1 ..< xb - left {
                                            p += 3
                                            red &+= p[0]
                                            green &+= p[1]
                                            blue &+= p[2]
                                            (p[0], p[1], p[2]) = (red, green, blue)
                                        }
                                    }
                                }
                                let firstOX = ((xa - x0 + 1) * ow - 1) / rw
                                for oy in oy0..<oy1 {
                                    let r0 = max(rows[oy], ra), r1 = min(rows[oy + 1], rb)
                                    guard r0 < r1 else { continue }
                                    let sum = sums.baseAddress! + (oy - oy0) * ow * 3
                                    if ow == rw {
                                        // One column per output pixel (a 100 % part): add the bytes straight across.
                                        for r in r0..<r1 {
                                            let line = block + ((r - top) * blockWidth + xa - left) * 3, to = sum + (xa - x0) * 3
                                            for i in 0 ..< (xb - xa) * 3 { to[i] += UInt64(line[i]) }
                                        }
                                        continue
                                    }
                                    for r in r0..<r1 {
                                        let line = block + (r - top) * blockWidth * 3
                                        var ox = firstOX
                                        while ox < ow, columns[ox] < xb {
                                            // One row of an output pixel fits in 32 bits: rows are at most 300,000 × 255.
                                            var s: (UInt32, UInt32, UInt32) = (0, 0, 0)
                                            for x in max(columns[ox], xa) ..< min(columns[ox + 1], xb) {
                                                let p = line + (x - left) * 3
                                                s.0 &+= UInt32(p[0])
                                                s.1 &+= UInt32(p[1])
                                                s.2 &+= UInt32(p[2])
                                            }
                                            sum[ox * 3] += UInt64(s.0)
                                            sum[ox * 3 + 1] += UInt64(s.1)
                                            sum[ox * 3 + 2] += UInt64(s.2)
                                            ox += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    failed.withLock { $0 = true }
                    return
                }
                for oy in oy0..<oy1 {
                    for ox in 0..<ow {
                        let count = UInt64((rows[oy + 1] - rows[oy]) * (columns[ox + 1] - columns[ox]))
                        let i = oy * ow * 4 + ox * 4, s = (oy - oy0) * ow * 3 + ox * 3
                        for c in 0..<3 { output[i + c] = UInt8((sums[s + c] + count / 2) / count) }
                        output[i + 3] = 255
                    }
                }
            }
        }
        guard !failed.withLock({ $0 }) else {
            output.deallocate()
            throw OwnDecodeError.corrupt
        }
        return try image(output, ow: ow, oh: oh)
    }

    /// Block `index`, `rows` rows of `blockWidth` RGB pixels, decompressed into `buffer`: at least its first
    /// `needed` bytes (LZW and raw stop there), the whole block for Deflate. `packed`: a reused read buffer.
    private func decodeBlock(_ index: Int, rows: Int, needed: Int, fd: Int32, packed: inout [UInt8],
                             into buffer: UnsafeMutablePointer<UInt8>) throws {
        let size = rows * blockWidth * 3
        if counts[index] == 0 { return buffer.initialize(repeating: 0, count: size) }
        if compression == 1 {
            guard counts[index] >= size else { throw OwnDecodeError.corrupt }
            return try FileRead.read(fd, offsets[index], needed, into: buffer)
        }
        let count = counts[index]
        if packed.count < count { packed = [UInt8](repeating: 0, count: count) }
        try packed.withUnsafeMutableBufferPointer { try FileRead.read(fd, offsets[index], count, into: $0.baseAddress!) }
        if compression == 5 {
            try packed.withUnsafeBufferPointer {
                try Self.lzw(UnsafeBufferPointer(rebasing: $0[..<count]), into: UnsafeMutableBufferPointer(start: buffer, count: size),
                             stoppingAt: needed)
            }
        } else {
            try Inflate.zlib(packed[..<count], filling: UnsafeMutableBufferPointer(start: buffer, count: size))
        }
    }

    /// TIFF LZW (MSB-first codes of 9 to 12 bits, Clear 256, EOI 257, each width change one code early) into
    /// `out`. Throws on a code past the table or a stream that ends before `out` is full, which also turns away
    /// old-style LSB-first LZW; codes past a full `out` (a padded strip) are left. `stop`: returns once that many bytes are out.
    static func lzw(_ packed: UnsafeBufferPointer<UInt8>, into out: UnsafeMutableBufferPointer<UInt8>,
                    stoppingAt stop: Int? = nil) throws {
        guard let base = out.baseAddress, let input = packed.baseAddress else { throw OwnDecodeError.corrupt }
        // Each code's string, already written: where it starts (in `out`, or for a single byte in `bytes`) and its
        // length. A code's string is the previous code's string plus the next byte written, so decoding is a copy.
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 256 + 16)  // 16 bytes over for the short copies below
        let starts = UnsafeMutablePointer<UnsafePointer<UInt8>>.allocate(capacity: 4096)
        let lengths = UnsafeMutablePointer<Int>.allocate(capacity: 4096)
        defer {
            bytes.deallocate()
            starts.deallocate()
            lengths.deallocate()
        }
        for b in 0..<256 {
            bytes[b] = UInt8(b)
            starts[b] = UnsafePointer(bytes + b)
            lengths[b] = 1
        }
        (bytes + 256).initialize(repeating: 0, count: 16)
        let end = out.count, stop = min(stop ?? end, end), totalBits = packed.count * 8
        // While 4 bytes remain, a code comes from one 4-byte load at its bit position; bit by bit at the end.
        let fastBits = (packed.count - 3) * 8
        var pos = 0, next = 258, width = 9, widenAt = 511, n = 0
        var oldStart = UnsafePointer(base), oldLength = 0
        @inline(__always) func read() -> Int? {
            if pos < fastBits {
                let word = UInt32(bigEndian: UnsafeRawPointer(input + pos >> 3).loadUnaligned(as: UInt32.self))
                let code = Int(truncatingIfNeeded: (word << UInt32(pos & 7)) >> UInt32(32 - width))
                pos += width
                return code
            }
            guard pos + width <= totalBits else { return nil }
            var code = 0
            for _ in 0..<width {
                code = code << 1 | Int(input[pos >> 3] >> (7 - UInt8(pos & 7)) & 1)
                pos += 1
            }
            return code
        }
        decoding: while true {
            guard var code = read() else { break }
            if UInt(bitPattern: code &- 256) < 2 {
                if code == 257 { break }
                (next, width, widenAt) = (258, 9, 511)
                // The first code after Clear: a single byte, and nothing added to the table.
                repeat {
                    guard let first = read() else { break decoding }
                    code = first
                } while code == 256
                if code == 257 { break }
                guard code < 256 else { throw OwnDecodeError.corrupt }
                guard n < end else { return }
                base[n] = UInt8(code)
                (oldStart, oldLength) = (UnsafePointer(base + n), 1)
                n += 1
                if n >= stop, stop < end { return }
                continue
            }
            let length: Int
            if code < next {
                length = lengths[code]
                guard n + length <= end else { return (base + n).update(from: starts[code], count: end - n) }
                let from = UnsafeRawPointer(starts[code]), to = UnsafeMutableRawPointer(base + n)
                // Short strings as one or two 8-byte copies, all loads before any store: the bytes past the
                // string are rewritten by the codes after it.
                if length <= 8, n + 8 <= end {
                    to.storeBytes(of: from.loadUnaligned(as: UInt64.self), as: UInt64.self)
                } else if length <= 16, n + 16 <= end {
                    let (a, b) = (from.loadUnaligned(as: UInt64.self), from.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
                    to.storeBytes(of: a, as: UInt64.self)
                    to.storeBytes(of: b, toByteOffset: 8, as: UInt64.self)
                } else {
                    to.copyMemory(from: from, byteCount: length)
                }
            } else if code == next, oldLength > 0 {
                // The string not yet in the table: the previous one plus its own first byte.
                length = oldLength + 1
                guard n + length <= end else { return (base + n).update(from: oldStart, count: end - n) }
                (base + n).update(from: oldStart, count: oldLength)
                base[n + oldLength] = oldStart[0]
            } else {
                throw OwnDecodeError.corrupt
            }
            // No previous string only for a stream that doesn't start with Clear.
            if next < 4096, oldLength > 0 {
                starts[next] = oldStart
                lengths[next] = oldLength + 1
                next += 1
                if next == widenAt, width < 12 {
                    width += 1
                    widenAt = (1 << width) - 1
                }
            }
            (oldStart, oldLength) = (UnsafePointer(base + n), length)
            n += length
            if n >= stop, stop < end { return }
        }
        guard n == end else { throw OwnDecodeError.corrupt }
    }
}
