import CoreGraphics
import Foundation
import os

/// The stored composite of an 8-bit RGB PSD or PSB (raw or PackBits RLE), read straight from the file:
/// only the rows a decode needs, in parallel bands, area-averaged to the size asked for. Huge pictures
/// open in a fraction of ImageIO's time and memory this way. Every other PSD/PSB is left to ImageIO.
public struct PSDComposite: Sendable {
    public let width: Int
    public let height: Int
    /// Image resource 1039's bytes, nil without one.
    public let icc: Data?

    private let url: URL
    /// Raw: where the first channel's first row starts.
    private let dataStart: Int
    /// RLE: where each channel row starts, channel by channel, plus the end (`3 × height + 1`); nil when raw.
    private let rowOffsets: [Int]?

    /// Reads only the header, the section lengths, the resource list and (RLE) the row byte-count table.
    /// Nil when the file isn't an 8-bit, 3-channel RGB PSD/PSB with a raw or RLE composite, or its header
    /// can't be followed.
    public init?(url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        let fileSize = Int(info.st_size)
        // Bounded by the file's size, so a damaged length never asks for a huge buffer.
        func bytes(_ offset: Int, _ count: Int) -> [UInt8]? {
            guard count >= 0, offset <= fileSize - count else { return nil }
            return try? Self.read(fd, offset, count)
        }
        func be(_ b: ArraySlice<UInt8>) -> Int { b.reduce(0) { $0 << 8 | Int($1) } }

        guard let header = bytes(0, 26), header[0..<4].elementsEqual("8BPS".utf8) else { return nil }
        let version = be(header[4..<6]), channels = be(header[12..<14])
        let height = be(header[14..<18]), width = be(header[18..<22])
        let depth = be(header[22..<24]), mode = be(header[24..<26])
        // PSB allows at most 300,000 per side, which also keeps decode's 32-bit row sums from overflowing.
        guard version == 1 || version == 2, channels == 3, depth == 8, mode == 3, (1...300_000).contains(width),
              (1...300_000).contains(height) else { return nil }

        var offset = 26
        guard let modeLength = bytes(offset, 4).map({ be($0[...]) }) else { return nil }
        offset += 4 + modeLength
        guard let resourceLength = bytes(offset, 4).map({ be($0[...]) }), let resources = bytes(offset + 4, resourceLength) else { return nil }
        offset += 4 + resourceLength
        var icc: Data?
        var r = 0
        while r + 12 <= resources.count {
            let id = be(resources[r + 4 ..< r + 6])
            let nameLength = (1 + Int(resources[r + 6]) + 1) & ~1
            let sizeAt = r + 6 + nameLength
            guard sizeAt + 4 <= resources.count else { return nil }
            let size = be(resources[sizeAt ..< sizeAt + 4])
            guard sizeAt + 4 + size <= resources.count else { return nil }
            if id == 1039 { icc = Data(resources[sizeAt + 4 ..< sizeAt + 4 + size]) }
            r = sizeAt + 4 + (size + 1) & ~1
        }
        let lengthSize = version == 1 ? 4 : 8
        guard let layerLength = bytes(offset, lengthSize).map({ be($0[...]) }), layerLength >= 0,
              layerLength <= fileSize - offset - lengthSize else { return nil }
        offset += lengthSize + layerLength
        guard let compression = bytes(offset, 2).map({ be($0[...]) }), compression == 0 || compression == 1 else { return nil }
        offset += 2

        if compression == 1 {
            let countSize = version == 1 ? 2 : 4, rows = channels * height
            guard let table = bytes(offset, rows * countSize) else { return nil }
            var offsets = [Int](repeating: 0, count: rows + 1)
            offsets[0] = offset + rows * countSize
            for i in 0..<rows { offsets[i + 1] = offsets[i] + be(table[i * countSize ..< (i + 1) * countSize]) }
            guard offsets[rows] <= fileSize else { return nil }
            rowOffsets = offsets
        } else {
            // Checked here so a decode never sizes its bands from a size the file can't hold.
            let (bytes, overflow) = (channels * width).multipliedReportingOverflow(by: height)
            guard !overflow, bytes <= fileSize - offset else { return nil }
            rowOffsets = nil
        }
        self.url = url
        self.width = width
        self.height = height
        self.icc = icc
        dataStart = offset
    }

    /// `region` in full-size pixels (integral, inside the picture; nil = the whole picture), area-averaged to
    /// `size`, which is clamped to at most the region and at least 1 × 1 per side. 8-bit RGB in the file's
    /// ICC profile (sRGB without a usable one). Throws `OwnDecodeError.corrupt` on any short read or bad RLE.
    public func decode(region: CGRect? = nil, size: PixelSize) throws -> CGImage {
        let rect = (region ?? CGRect(x: 0, y: 0, width: width, height: height)).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { throw OwnDecodeError.corrupt }
        let x0 = Int(rect.minX), y0 = Int(rect.minY), rw = Int(rect.width), rh = Int(rect.height)
        let ow = min(max(size.width, 1), rw), oh = min(max(size.height, 1), rh)
        let columns = (0...ow).map { x0 + $0 * rw / ow }

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw OwnDecodeError.corrupt }
        defer { close(fd) }

        let bytesPerRow = ow * 4
        // Each iteration writes only its own output row.
        nonisolated(unsafe) let output = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bytesPerRow * oh)
        let failed = OSAllocatedUnfairLock(initialState: false)
        let (width, height, dataStart, rowOffsets) = (width, height, dataStart, rowOffsets)
        DispatchQueue.concurrentPerform(iterations: oh) { oy in
            let r0 = y0 + oy * rh / oh, r1 = y0 + (oy + 1) * rh / oh
            let sums = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: ow * 3)
            sums.initialize(repeating: 0)
            defer { sums.deallocate() }
            // About 1 MB of rows per read, so a small decode of a huge picture holds little per band.
            let chunk = max(1, (1 << 20) / (rowOffsets == nil ? rw : width))
            // Raw rows land in one buffer per output row: a fresh one per read costs page faults on every chunk.
            let scratch = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: rowOffsets == nil ? chunk * rw : 0)
            defer { scratch.deallocate() }
            do {
                for c in 0..<3 {
                    for a in stride(from: r0, to: r1, by: chunk) {
                        let b = min(a + chunk, r1)
                        // RLE rows unpack whole (stride `width`, column 0 first); raw rows read only the region's columns.
                        func add(_ band: UnsafePointer<UInt8>, rowStride: Int, start: Int) {
                            for row in 0..<(b - a) {
                                let line = band + row * rowStride - start
                                columns.withUnsafeBufferPointer { columns in
                                    for ox in 0..<ow {
                                        // One row of an output pixel fits in 32 bits: PSB rows are at most 300,000 × 255.
                                        var sum: UInt32 = 0
                                        for x in columns[ox]..<columns[ox + 1] { sum &+= UInt32(line[x]) }
                                        sums[ox * 3 + c] += UInt64(sum)
                                    }
                                }
                            }
                        }
                        if let offsets = rowOffsets {
                            let first = c * height + a
                            let packed = try Self.read(fd, offsets[first], offsets[first + b - a] - offsets[first])
                            let band = try (a..<b).flatMap { r -> [UInt8] in
                                let from = offsets[c * height + r] - offsets[first], to = offsets[c * height + r + 1] - offsets[first]
                                return try Self.unpackBits(packed[from..<to], width: width)
                            }
                            band.withUnsafeBufferPointer { add($0.baseAddress!, rowStride: width, start: 0) }
                        } else {
                            try Self.rawBand(channel: c, rows: a..<b, x0: x0, rw: rw, width: width, height: height,
                                             dataStart: dataStart, into: scratch.baseAddress!) { try Self.read(fd, $0, $1, into: $2) }
                            add(scratch.baseAddress!, rowStride: rw, start: x0)
                        }
                    }
                }
            } catch {
                failed.withLock { $0 = true }
                return
            }
            let rows = UInt64(r1 - r0)
            for ox in 0..<ow {
                let count = rows * UInt64(columns[ox + 1] - columns[ox])
                let i = oy * bytesPerRow + ox * 4
                for c in 0..<3 { output[i + c] = UInt8((sums[ox * 3 + c] + count / 2) / count) }
                output[i + 3] = 255
            }
        }
        let data = Data(bytesNoCopy: output.baseAddress!, count: output.count, deallocator: .custom { pointer, _ in pointer.deallocate() })
        guard !failed.withLock({ $0 }) else { throw OwnDecodeError.corrupt }

        let space = icc.flatMap { CGColorSpace(iccData: $0 as CFData) }.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw OwnDecodeError.corrupt }
        return image
    }

    /// Rows `rows` of raw channel `c`, columns `x0 ..< x0 + rw`, into `buffer` (`rows.count × rw` bytes):
    /// one read for full-width rows, else one per row. `read(offset, count, destination)`.
    static func rawBand(channel c: Int, rows: Range<Int>, x0: Int, rw: Int, width: Int, height: Int, dataStart: Int,
                        into buffer: UnsafeMutablePointer<UInt8>,
                        read: (Int, Int, UnsafeMutablePointer<UInt8>) throws -> Void) rethrows {
        if rw == width { return try read(dataStart + (c * height + rows.lowerBound) * width, rows.count * width, buffer) }
        for (i, r) in rows.enumerated() { try read(dataStart + (c * height + r) * width + x0, rw, buffer + i * rw) }
    }

    /// `count` bytes at `offset`; throws on an error or the end of the file before them.
    private static func read(_ fd: Int32, _ offset: Int, _ count: Int) throws -> [UInt8] {
        try [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            try read(fd, offset, count, into: buffer.baseAddress!)
            initialized = count
        }
    }

    /// `count` bytes at `offset` into `buffer`; throws on an error or the end of the file before them.
    private static func read(_ fd: Int32, _ offset: Int, _ count: Int, into buffer: UnsafeMutablePointer<UInt8>) throws {
        guard offset >= 0, count >= 0 else { throw OwnDecodeError.corrupt }
        var done = 0
        while done < count {
            let n = pread(fd, buffer + done, count - done, off_t(offset + done))
            guard n > 0 else { throw OwnDecodeError.corrupt }
            done += n
        }
    }

    /// One PackBits row; throws unless it comes out at exactly `width` bytes.
    private static func unpackBits(_ packed: ArraySlice<UInt8>, width: Int) throws -> [UInt8] {
        var row: [UInt8] = []
        row.reserveCapacity(width)
        var i = packed.startIndex
        while i < packed.endIndex {
            let n = Int(Int8(bitPattern: packed[i]))
            i += 1
            if n >= 0 {
                guard i + n + 1 <= packed.endIndex, row.count + n + 1 <= width else { throw OwnDecodeError.corrupt }
                row += packed[i ..< i + n + 1]
                i += n + 1
            } else if n > -128 {
                guard i < packed.endIndex, row.count + 1 - n <= width else { throw OwnDecodeError.corrupt }
                row += repeatElement(packed[i], count: 1 - n)
                i += 1
            }
        }
        guard row.count == width else { throw OwnDecodeError.corrupt }
        return row
    }
}
