import Accelerate
import Compression
import Foundation
import os

/// A rectangle in canvas pixels, as Photoshop stores it: bottom and right exclusive.
public typealias PSDRect = (top: Int, left: Int, bottom: Int, right: Int)

/// The layer and mask section of an 8-bit RGB PSD or PSB (Adobe's *Photoshop File Formats Specification*):
/// the layer records as a tree, bottom to top, and the section's own tagged blocks. Channel pixels stay in
/// the file until a layer's `channels(scale:)` reads them.
public struct PSDLayers: Sendable {
    public let width: Int
    public let height: Int
    /// Bottom to top.
    public let nodes: [PSDNode]
    /// False when version info (resource 1057) says the stored composite isn't the picture.
    public let hasRealComposite: Bool
    /// The tagged blocks after the layer info (patterns, linked files and the like).
    public let globalBlocks: [String: Data]
    /// The ICC profile (image resource 1039) the pixels are in, nil without one.
    public let profile: Data?

    /// Tagged block keys left in the file: embedded files, filter data and layer data, which can run to
    /// hundreds of MB and nothing reads. shortcut: dropped, not indexed; record offset and length when one is needed.
    /// Deepest group nesting accepted: Photoshop allows about 10; deeper files are refused, since drawing and freeing
    /// the tree recurse once per level and each isolated level holds a scaled canvas.
    static let maxGroupDepth = 16
    /// Test hook: how many files were opened for their layers in this task.
    @TaskLocal static var opened: OSAllocatedUnfairLock<Int>?
    static let unreadKeys: Set<String> = ["lnk2", "lnkD", "lnk3", "lnkE", "FEid", "FXid", "Layr", "Lr16", "Lr32", "PxSD"]

    /// Tagged block keys whose length is 8 bytes in a PSB.
    static let longKeys: Set<String> = ["LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD"]

    /// Nil for anything but an 8-bit RGB PSD/PSB with 3 or more channels; throws `OwnDecodeError.corrupt`
    /// when the layer section can't be followed.
    public init?(url: URL) throws {
        Self.opened?.withLock { $0 += 1 }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw FileRead.error() }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw FileRead.error() }
        var r = FileCursor(fd: fd, end: Int(info.st_size))

        guard r.end >= 26, try r.bytes(4).elementsEqual("8BPS".utf8) else { return nil }
        let version = try r.int(2)
        try r.skip(6)
        let channelCount = try r.int(2), height = try r.int(4), width = try r.int(4), depth = try r.int(2), mode = try r.int(2)
        guard version == 1 || version == 2, channelCount >= 3, depth == 8, mode == 3,
              (1...300_000).contains(width), (1...300_000).contains(height) else { return nil }
        let long = version == 1 ? 4 : 8

        try r.skip(try r.int(4))
        let resources = try r.bytes(try r.int(4))
        var hasRealComposite = true, profile: Data?
        var i = resources.startIndex
        func be(_ b: ArraySlice<UInt8>) -> Int { b.reduce(0) { $0 << 8 | Int($1) } }
        while i + 12 <= resources.endIndex {
            let id = be(resources[i + 4 ..< i + 6])
            let sizeAt = i + 6 + ((1 + Int(resources[i + 6]) + 1) & ~1)
            guard sizeAt + 4 <= resources.endIndex else { throw OwnDecodeError.corrupt }
            let size = be(resources[sizeAt ..< sizeAt + 4])
            guard size <= resources.endIndex - sizeAt - 4 else { throw OwnDecodeError.corrupt }
            if id == 1057, size >= 5 { hasRealComposite = resources[sizeAt + 8] != 0 }
            if id == 1039 { profile = Data(resources[sizeAt + 4 ..< sizeAt + 4 + size]) }
            i = sizeAt + 4 + (size + 1) & ~1
        }

        let sectionEnd = try r.lengthEnd(long)
        var records: [Record] = []
        if r.offset < sectionEnd {
            let infoEnd = try r.lengthEnd(long)
            guard infoEnd <= sectionEnd else { throw OwnDecodeError.corrupt }
            if r.offset < infoEnd {
                let count = abs(Int(Int16(truncatingIfNeeded: try r.int(2))))
                for _ in 0..<count { records.append(try Record(&r, version: version, end: infoEnd)) }
                var at = r.offset
                for k in records.indices {
                    for (id, length) in records[k].channelLengths {
                        guard length >= 0, length <= infoEnd - at else { throw OwnDecodeError.corrupt }
                        records[k].source.channels[id] = (at, length)
                        at += length
                    }
                }
            }
            r.offset = infoEnd
        }
        if sectionEnd - r.offset >= 4 { try r.skip(try r.int(4)) }  // global layer mask info
        guard r.offset <= sectionEnd else { throw OwnDecodeError.corrupt }
        globalBlocks = try r.blocks(until: sectionEnd, version: version)

        // Records run bottom to top; a divider opens a group's children, its folder record closes them.
        var stack: [[PSDNode]] = [[]]
        for var record in records {
            record.source.url = url
            record.source.version = version
            record.source.canvas = (width, height)
            let layer = record.layer
            if let section = layer.blocks["lsct"] ?? layer.blocks["lsdk"], section.count >= 4 {
                let kind = be(Array(section.prefix(4))[...])
                if kind == 3 {
                    guard stack.count <= Self.maxGroupDepth else { throw OwnDecodeError.corrupt }
                    stack.append([])
                    continue
                }
                if kind == 1 || kind == 2 {
                    guard stack.count > 1 else { throw OwnDecodeError.corrupt }
                    let children = stack.removeLast()
                    let blend = section.count >= 12 ? String(decoding: section.dropFirst(8).prefix(4), as: UTF8.self) : layer.blend
                    stack[stack.count - 1].append(.group(PSDGroup(
                        name: layer.name, blend: blend, opacity: layer.opacity, visible: layer.visible, mask: layer.mask,
                        clipped: layer.clipped, blendIf: layer.blendIf, fill: layer.fill, vectorDensity: layer.vectorDensity,
                        vectorFeather: layer.vectorFeather, blocks: layer.blocks, children: children)))
                    continue
                }
            }
            stack[stack.count - 1].append(.layer(layer))
        }
        guard stack.count == 1 else { throw OwnDecodeError.corrupt }
        self.width = width
        self.height = height
        self.nodes = stack[0]
        self.hasRealComposite = hasRealComposite
        self.profile = profile
    }

    /// A scaled canvas side: `n × scale` rounded, at least 1.
    static func scaledSize(_ n: Int, _ scale: Double) -> Int { max(1, Int((Double(n) * min(scale, 1)).rounded())) }

    /// Whether `scale` leaves `canvas` at full size, so each cell is one canvas pixel.
    static func isFullSize(_ canvas: (width: Int, height: Int), _ scale: Double) -> Bool {
        scaledSize(canvas.width, scale) == canvas.width && scaledSize(canvas.height, scale) == canvas.height
    }

    /// Canvas cells as `PSDComposite` cuts them: scaled cell `X` of a side `n` long, `s` scaled, covers canvas
    /// coordinates `⌊X·n/s⌋ ..< ⌊(X+1)·n/s⌋`; this is the cell holding canvas coordinate `c` (also outside the canvas).
    static func cell(_ c: Int, _ n: Int, _ s: Int) -> Int { floorDiv((c + 1) * s - 1, n) }
    static func cellStart(_ x: Int, _ n: Int, _ s: Int) -> Int { floorDiv(x * n, s) }
    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    /// `rect` in the canvas scaled to `max(1, round(width × scale)) × max(1, round(height × scale))`: the cells it touches.
    static func scaled(_ rect: PSDRect, canvas: (width: Int, height: Int), scale: Double) -> PSDRect {
        let sw = scaledSize(canvas.width, scale), sh = scaledSize(canvas.height, scale)
        let top = cell(rect.top, canvas.height, sh), left = cell(rect.left, canvas.width, sw)
        guard rect.bottom > rect.top, rect.right > rect.left else { return (top, left, top, left) }
        return (top, left, cell(rect.bottom - 1, canvas.height, sh) + 1, cell(rect.right - 1, canvas.width, sw) + 1)
    }
}

public indirect enum PSDNode: Sendable {
    case layer(PSDLayer)
    case group(PSDGroup)
}

public struct PSDGroup: Sendable {
    public let name: String
    /// 4-character blend key; "pass" is pass-through.
    public let blend: String
    public let opacity: UInt8
    public let visible: Bool
    public let mask: PSDMask?
    public let clipped: Bool
    public let blendIf: PSDBlendIf?
    /// Fill opacity (`iOpa`), 255 without one.
    public let fill: UInt8
    /// The vector mask's density (`PSDFills.vectorMask`), 255 without one.
    public let vectorDensity: UInt8
    /// The vector mask's feather radius in canvas pixels, 0 without one.
    public let vectorFeather: Double
    /// The folder record's tagged blocks.
    public let blocks: [String: Data]
    /// Bottom to top.
    public let children: [PSDNode]
}

public struct PSDLayer: Sendable {
    public let name: String
    public let rect: PSDRect
    /// 4-character blend key.
    public let blend: String
    public let opacity: UInt8
    /// Fill opacity (`iOpa`), 255 without one.
    public let fill: UInt8
    public let clipped: Bool
    public let visible: Bool
    public let mask: PSDMask?
    public let blendIf: PSDBlendIf?
    /// The vector mask's density (`PSDFills.vectorMask`), 255 without one.
    public let vectorDensity: UInt8
    /// The vector mask's feather radius in canvas pixels, 0 without one.
    public let vectorFeather: Double
    public let blocks: [String: Data]
    let source: PSDChannelSource

    /// Where `channels(scale:)` lands in the scaled canvas (see `PSDLayers.scaled`): the part of `rect` on the canvas.
    public func scaledRect(scale: Double) -> PSDRect { PSDLayers.scaled(source.clip(rect), canvas: source.canvas, scale: scale) }

    /// The layer's R, G, B and transparency on the canvas, straight colour, read from the file now and
    /// area-averaged to `scale` (≤ 1); its top-left sits at `scaledRect(scale:)`'s. Nil for an empty layer
    /// or one wholly off the canvas.
    public func channels(scale: Double) throws -> RGBAImage? {
        let clip = source.clip(rect)
        let w = clip.right - clip.left, h = clip.bottom - clip.top
        guard w > 0, h > 0, try source.holds([-1, 0, 1, 2], rect) else { return nil }
        if PSDLayers.isFullSize(source.canvas, scale) {
            let read = try source.reading(rect, opening: [0, 1, 2, -1]) { read in try [0, 1, 2, -1].map { try read($0, 0..<h) } }
            let none = read[0...2].contains { $0 == nil } ? [UInt8](repeating: 0, count: w * h) : []
            let planar = [read[0] ?? none, read[1] ?? none, read[2] ?? none, read[3] ?? [UInt8](repeating: 255, count: w * h)]
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            func buffer(_ p: UnsafeRawPointer, _ bytesPerPixel: Int) -> vImage_Buffer {
                vImage_Buffer(data: UnsafeMutableRawPointer(mutating: p), height: vImagePixelCount(h), width: vImagePixelCount(w),
                              rowBytes: w * bytesPerPixel)
            }
            planar[0].withUnsafeBytes { r in planar[1].withUnsafeBytes { g in planar[2].withUnsafeBytes { b in
                planar[3].withUnsafeBytes { a in pixels.withUnsafeMutableBytes { out in
                    // The planes in the order they land in each pixel: R, G, B, A.
                    var r = buffer(r.baseAddress!, 1), g = buffer(g.baseAddress!, 1), b = buffer(b.baseAddress!, 1)
                    var a = buffer(a.baseAddress!, 1), dest = buffer(out.baseAddress!, 4)
                    vImageConvert_Planar8toARGB8888(&r, &g, &b, &a, &dest, vImage_Flags(kvImageNoFlags))
                } }
            } } }
            return RGBAImage(width: w, height: h, pixels: pixels)
        }
        return try source.reading(rect, opening: [0, 1, 2, -1]) { read in
            let target = scaledRect(scale: scale)
            let ow = target.right - target.left, oh = target.bottom - target.top
            let cells = source.cells(clip, scale: scale)
            // Colour weighted by alpha, so transparent pixels don't tint their cell.
            var sums = [Int](repeating: 0, count: ow * oh * 4)  // R·A, G·A, B·A, A
            for band in source.bands(w, h) {
                let alpha = try read(-1, band), colour = try (0..<3).map { try read($0, band) }
                let none = [UInt8](repeating: 0, count: band.count * w)
                let planes = colour.map { $0 ?? none } + [alpha ?? [UInt8](repeating: 255, count: band.count * w)]
                // Runs of rows that start a scaled row, so no two runs add to the same cells: on all cores.
                let starts = band.filter { $0 == band.lowerBound || cells.rows[$0] != cells.rows[$0 - 1] }
                let runs = min(starts.count, ProcessInfo.processInfo.activeProcessorCount * 2)
                planes[0].withUnsafeBufferPointer { r in planes[1].withUnsafeBufferPointer { g in
                    planes[2].withUnsafeBufferPointer { b in planes[3].withUnsafeBufferPointer { a in
                        cells.columns.withUnsafeBufferPointer { columns in sums.withUnsafeMutableBufferPointer { sums in
                            // The planes are only read; each run adds only to its own scaled rows' sums.
                            nonisolated(unsafe) let r = r.baseAddress!, g = g.baseAddress!, b = b.baseAddress!, a = a.baseAddress!
                            nonisolated(unsafe) let columns = columns.baseAddress!, sums = sums.baseAddress!  // as above
                            let width = cells.columnAreas.count
                            DispatchQueue.concurrentPerform(iterations: runs) { run in
                                let from = starts[run * starts.count / runs]
                                let to = run + 1 == runs ? band.upperBound : starts[(run + 1) * starts.count / runs]
                                for y in from..<to {
                                    let row = cells.rows[y] * width, start = (y - band.lowerBound) * w
                                    for x in 0..<w {
                                        let p = start + x, o = (row + columns[x]) * 4, alpha = Int(a[p])
                                        sums[o] += Int(r[p]) * alpha
                                        sums[o + 1] += Int(g[p]) * alpha
                                        sums[o + 2] += Int(b[p]) * alpha
                                        sums[o + 3] += alpha
                                    }
                                }
                            }
                        } }
                    } }
                } }
            }
            var pixels = [UInt8](repeating: 0, count: ow * oh * 4)
            sums.withUnsafeBufferPointer { sums in pixels.withUnsafeMutableBufferPointer { pixels in
                // Each row writes only its own pixels; the sums are only read.
                nonisolated(unsafe) let sums = sums.baseAddress!, pixels = pixels.baseAddress!
                DispatchQueue.concurrentPerform(iterations: oh) { y in
                    for o in y * ow ..< (y + 1) * ow {
                        let alpha = sums[o * 4 + 3]
                        if alpha > 0 { for c in 0..<3 { pixels[o * 4 + c] = UInt8((sums[o * 4 + c] + alpha / 2) / alpha) } }
                        let area = cells.area(o - y * ow, y)
                        pixels[o * 4 + 3] = UInt8((alpha + area / 2) / area)
                    }
                }
            } }
            return RGBAImage(width: ow, height: oh, pixels: pixels)
        }
    }
}

public struct PSDMask: Sendable {
    public let rect: PSDRect
    /// The mask's value outside `rect`.
    public let defaultColour: UInt8
    public let disabled: Bool
    /// The position is relative to the layer.
    public let relative: Bool
    /// How strongly the mask hides: 255 fully, lower values lift its black toward white.
    public let density: UInt8
    /// The radius of the blur that softens its edges, in canvas pixels; 0 for none.
    public let feather: Double
    let channel: Int
    let source: PSDChannelSource

    /// `value` at the mask's density.
    func dense(_ value: UInt8) -> UInt8 { 255 - UInt8((Int(density) * (255 - Int(value)) + 127) / 255) }

    /// The mask's values over its scaled `rect` on the canvas (see `PSDLayers.scaled`), area-averaged with
    /// the default colour outside `rect`, at its density; one byte per pixel.
    public func pixels(scale: Double) throws -> (rect: PSDRect, pixels: [UInt8]) {
        var (rect, pixels) = try values(scale: scale)
        if feather > 0 { (rect, pixels) = Self.blur(rect, pixels, outside: defaultColour, sigma: feather * min(scale, 1)) }
        return (rect, density == 255 ? pixels : pixels.map(dense))
    }

    /// `pixels` over `rect` blurred by a Gaussian of `sigma` (Photoshop's feather radius), over `rect` grown by three
    /// sigmas: `outside` beyond `rect`, or its nearest edge pixel when nil. Three box blurs make the Gaussian, so the
    /// cost doesn't grow with the radius.
    static func blur(_ rect: PSDRect, _ pixels: [UInt8], outside: UInt8?, sigma: Double) -> (PSDRect, [UInt8]) {
        let margin = Int((3 * sigma).rounded(.up))
        guard margin > 0, rect.bottom > rect.top, rect.right > rect.left else { return (rect, pixels) }
        let w = rect.right - rect.left, h = rect.bottom - rect.top, bw = w + 2 * margin, bh = h + 2 * margin
        var plane = [UInt8](repeating: outside ?? 0, count: bw * bh)
        for y in 0..<bh {
            let sy = min(max(y - margin, 0), h - 1)
            guard outside == nil || (margin..<margin + h).contains(y) else { continue }
            for x in 0..<bw where outside == nil || (margin..<margin + w).contains(x) {
                plane[y * bw + x] = pixels[sy * w + min(max(x - margin, 0), w - 1)]
            }
        }
        // Widths of three boxes whose variances add up to sigma² (odd sizes, the smaller ones first).
        let ideal = (12 * sigma * sigma / 3 + 1).squareRoot()
        var lower = Int(ideal.rounded(.down)); if lower % 2 == 0 { lower -= 1 }
        let upper = lower + 2
        let small = Int(((12 * sigma * sigma - 3 * Double(lower * lower) - 12 * Double(lower) - 9) / Double(-4 * lower - 4)).rounded())
        var out = plane
        plane.withUnsafeMutableBytes { a in
            out.withUnsafeMutableBytes { b in
                var src = vImage_Buffer(data: a.baseAddress, height: vImagePixelCount(bh), width: vImagePixelCount(bw), rowBytes: bw)
                var dst = vImage_Buffer(data: b.baseAddress, height: vImagePixelCount(bh), width: vImagePixelCount(bw), rowBytes: bw)
                for pass in 0..<3 {
                    let size = UInt32(max(1, pass < small ? lower : upper))
                    vImageBoxConvolve_Planar8(&src, &dst, nil, 0, 0, size, size, 0, vImage_Flags(kvImageEdgeExtend))
                    swap(&src, &dst)
                }
            }
        }
        // Three passes leave the result in the second buffer.
        return ((rect.top - margin, rect.left - margin, rect.bottom + margin, rect.right + margin), out)
    }

    private func values(scale: Double) throws -> (rect: PSDRect, pixels: [UInt8]) {
        let clip = source.clip(rect)
        let w = clip.right - clip.left, h = clip.bottom - clip.top
        let target = PSDLayers.scaled(clip, canvas: source.canvas, scale: scale)
        let ow = target.right - target.left, oh = target.bottom - target.top
        // Without its channel the mask is the default colour everywhere.
        guard w > 0, h > 0, try source.holds([channel], rect) else { return ((target.top, target.left, target.top, target.left), []) }
        return try source.reading(rect) { read in
            if PSDLayers.isFullSize(source.canvas, scale) {
                return (target, try read(channel, 0..<h) ?? [UInt8](repeating: defaultColour, count: w * h))
            }
            let cells = source.cells(clip, scale: scale)
            var sums = [Int](repeating: 0, count: ow * oh), counts = sums
            for band in source.bands(w, h) {
                let plane = try read(channel, band)
                for y in band {
                    for x in 0..<w {
                        let o = cells.index(x, y)
                        sums[o] += plane.map { Int($0[(y - band.lowerBound) * w + x]) } ?? Int(defaultColour)
                        counts[o] += 1
                    }
                }
            }
            let out = (0..<ow * oh).map { o -> UInt8 in
                let area = cells.area(o % ow, o / ow)
                return UInt8((sums[o] + (area - counts[o]) * Int(defaultColour) + area / 2) / area)
            }
            return (target, out)
        }
    }
}

/// Blend If: black low, black high, white low, white high, for this layer (source) and what lies below (backdrop).
public struct PSDBlendIf: Sendable {
    public typealias Range = (source: [UInt8], backdrop: [UInt8])
    public let gray: Range
    public let red: Range
    public let green: Range
    public let blue: Range
}

/// Where one layer's channels sit in the file.
struct PSDChannelSource: Sendable {
    var url = URL(fileURLWithPath: "/")
    var version = 1
    var canvas = (width: 1, height: 1)
    /// Channel ID → offset and length (compression field included).
    var channels: [Int: (offset: Int, length: Int)] = [:]

    /// Test hook: the largest buffer of channel bytes (read, unpacked or inflated) a read in this task held.
    @TaskLocal static var largestRead: OSAllocatedUnfairLock<Int>?
    static func held(_ bytes: Int) { largestRead?.withLock { $0 = max($0, bytes) } }

    /// `rect`'s part on the canvas (empty, at the nearest edge, when it has none).
    func clip(_ rect: PSDRect) -> PSDRect {
        let top = min(max(rect.top, 0), canvas.height), left = min(max(rect.left, 0), canvas.width)
        return (top, left, max(top, min(rect.bottom, canvas.height)), max(left, min(rect.right, canvas.width)))
    }

    /// Runs `body` with a reader of the channels of a layer or mask at `rect`: `read(id, rows)` gives rows `rows`
    /// of `clip(rect)` (0 its top), row by row; nil when there's no such channel. A failed read throws `POSIXError`, any
    /// other failure `OwnDecodeError.corrupt`.
    /// Reading rows of one of the channels `opening` reads the same rows of all of them at once, on all cores.
    func reading<T>(_ rect: PSDRect, opening: [Int] = [],
                    _ body: ((Int, Range<Int>) throws -> [UInt8]?) throws -> T) throws -> T {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw FileRead.error() }
        defer { close(fd) }
        var opened: [Int: Channel] = [:], ahead: [Int: (rows: Range<Int>, bytes: [UInt8])] = [:]
        do {
            return try body { id, rows in
                guard channels[id] != nil else { return nil }
                if let read = ahead.removeValue(forKey: id), read.rows == rows { return read.bytes }
                let ids = opening.contains(id) ? opening.filter { channels[$0] != nil } : [id]
                for i in ids where opened[i] == nil {
                    let (offset, length) = channels[i]!
                    opened[i] = try self.channel(fd, offset, length, rect)
                }
                let channels = ids.map { opened[$0]! }, hook = Self.largestRead
                let read = OSAllocatedUnfairLock(initialState: [Int: Result<[UInt8], Error>]())
                // Each iteration reads its own channel.
                DispatchQueue.concurrentPerform(iterations: ids.count) { k in
                    let bytes = Self.$largestRead.withValue(hook) { Result { try self.band(fd, channels[k], rect, rows) } }
                    read.withLock { $0[ids[k]] = bytes }
                }
                let done = read.withLock { $0 }
                for i in ids where i != id { ahead[i] = (rows, try done[i]!.get()) }
                return try done[id]!.get()
            }
        } catch let error as POSIXError {
            throw error
        } catch {
            throw OwnDecodeError.corrupt
        }
    }

    /// Row ranges of about 1 MB of a `w`-wide plane `h` rows high, so a small decode of a huge layer holds little.
    func bands(_ w: Int, _ h: Int) -> [Range<Int>] {
        let rows = max(1, (1 << 20) / w)
        return stride(from: 0, to: h, by: rows).map { $0 ..< min($0 + rows, h) }
    }

    /// False when none of `ids` is in the file; throws `OwnDecodeError.corrupt` when one that is can't unpack to
    /// all of `rect` by its own compression, so a damaged rect can't ask for more than the file holds.
    func holds(_ ids: [Int], _ rect: PSDRect) throws -> Bool {
        let w = rect.right - rect.left, h = rect.bottom - rect.top
        let present = ids.compactMap { channels[$0] }
        guard !present.isEmpty else { return false }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw FileRead.error() }
        defer { close(fd) }
        for (offset, length) in present {
            guard length >= 2 else { throw OwnDecodeError.corrupt }
            let head = try FileRead.bytes(fd, offset, 2)
            guard fits(Int(head[0]) << 8 | Int(head[1]), length - 2, w, h) else { throw OwnDecodeError.corrupt }
        }
        return true
    }

    /// Whether `body` bytes of `compression` can unpack to `w × h`.
    private func fits(_ compression: Int, _ body: Int, _ w: Int, _ h: Int) -> Bool {
        switch compression {
        case 0: body >= w * h
        // Row byte counts, then PackBits' at least 2 bytes per 128 pixels of a row.
        case 1: body >= h * (version == 1 ? 2 : 4) + h * 2 * ((w + 127) / 128)
        // Deflate packs at most about 1032 to 1.
        case 2, 3: w * h <= body * 1100
        default: false
        }
    }

    /// Where a channel's rows of `clip(rect)` are.
    private enum Channel: Sendable {
        /// The file offset of the clip's first byte.
        case raw(Int)
        /// The file offsets of the clip's packed rows and the end of the last.
        case rle([Int])
        /// The stream, inflated row by row as rows are asked for.
        case zip(ZipRows)
    }

    /// A layer's or mask's channel at `rect`, checked against its compression; only its part on the canvas:
    /// raw and RLE rows off the canvas aren't read.
    private func channel(_ fd: Int32, _ offset: Int, _ length: Int, _ rect: PSDRect) throws -> Channel {
        let w = rect.right - rect.left, h = rect.bottom - rect.top, clip = clip(rect)
        let x0 = clip.left - rect.left, y0 = clip.top - rect.top, cw = clip.right - clip.left, ch = clip.bottom - clip.top
        guard length >= 2, cw > 0, ch > 0 else { throw OwnDecodeError.corrupt }
        let head = try FileRead.bytes(fd, offset, 2), compression = Int(head[0]) << 8 | Int(head[1])
        guard fits(compression, length - 2, w, h) else { throw OwnDecodeError.corrupt }
        switch compression {
        case 0:
            return .raw(offset + 2 + y0 * w + x0)
        case 1:
            let countSize = version == 1 ? 2 : 4, rowsAt = 2 + h * countSize
            let counts = try FileRead.bytes(fd, offset + 2, h * countSize)
            func count(_ y: Int) -> Int { (0..<countSize).reduce(0) { $0 << 8 | Int(counts[y * countSize + $1]) } }
            let skipped = (0..<y0).reduce(0) { $0 + count($1) }
            var starts = [offset + rowsAt + skipped]
            for y in y0 ..< y0 + ch { starts.append(starts[starts.count - 1] + count(y)) }
            guard starts[ch] > starts[0], starts[ch] <= offset + length else { throw OwnDecodeError.corrupt }
            return .rle(starts)
        case 2, 3:
            return .zip(try ZipRows(fd: fd, offset: offset + 2, length: length - 2, width: w, predicted: compression == 3))
        default:
            throw OwnDecodeError.corrupt
        }
    }

    /// Rows `rows` of `channel`'s part of `clip(rect)`.
    private func band(_ fd: Int32, _ channel: Channel, _ rect: PSDRect, _ rows: Range<Int>) throws -> [UInt8] {
        let w = rect.right - rect.left, clip = clip(rect), x0 = clip.left - rect.left, cw = clip.right - clip.left
        var out = [UInt8](repeating: 0, count: rows.count * cw)
        switch channel {
        case .raw(let at):
            try out.withUnsafeMutableBufferPointer { out in
                for (i, y) in rows.enumerated() { try FileRead.read(fd, at + y * w, cw, into: out.baseAddress! + i * cw) }
            }
        case .rle(let starts):
            let data = try FileRead.bytes(fd, starts[rows.lowerBound], starts[rows.upperBound] - starts[rows.lowerBound])
            Self.held(data.count)
            var row = [UInt8](repeating: 0, count: x0 + cw)
            var at = 0
            try data.withUnsafeBufferPointer { data in
                try row.withUnsafeMutableBufferPointer { row in
                    for (i, y) in rows.enumerated() {
                        let n = starts[y + 1] - starts[y]
                        try PSDComposite.unpackBits(UnsafeBufferPointer(rebasing: data[at ..< at + n]), width: w, into: row)
                        out.replaceSubrange(i * cw ..< (i + 1) * cw, with: row[x0...])
                        at += n
                    }
                }
            }
        case .zip(let zip):
            let y0 = clip.top - rect.top
            try out.withUnsafeMutableBufferPointer {
                try zip.rows(y0 + rows.lowerBound ..< y0 + rows.upperBound, x0 ..< x0 + cw, into: $0.baseAddress!)
            }
        }
        Self.held(out.count)
        return out
    }

    /// Maps each pixel of `rect` to its cell in `rect` scaled.
    func cells(_ rect: PSDRect, scale: Double) -> Cells {
        let target = PSDLayers.scaled(rect, canvas: canvas, scale: scale)
        func side(_ from: Int, _ to: Int, _ scaledFrom: Int, _ scaledTo: Int, _ n: Int) -> ([Int], [Int]) {
            let s = PSDLayers.scaledSize(n, scale)
            return ((from..<to).map { PSDLayers.cell($0, n, s) - scaledFrom },
                    (scaledFrom..<scaledTo).map { PSDLayers.cellStart($0 + 1, n, s) - PSDLayers.cellStart($0, n, s) })
        }
        let (columns, columnAreas) = side(rect.left, rect.right, target.left, target.right, canvas.width)
        let (rows, rowAreas) = side(rect.top, rect.bottom, target.top, target.bottom, canvas.height)
        return Cells(columns: columns, rows: rows, columnAreas: columnAreas, rowAreas: rowAreas)
    }
}

/// One scaled rect's cells: which cell each source pixel falls in, and each cell's area in canvas pixels.
struct Cells {
    let columns: [Int], rows: [Int]
    let columnAreas: [Int], rowAreas: [Int]

    func index(_ x: Int, _ y: Int) -> Int { rows[y] * columnAreas.count + columns[x] }
    func area(_ x: Int, _ y: Int) -> Int { columnAreas[x] * rowAreas[y] }
}

/// Reads a file through a 64 KB window; every read past `end` throws `OwnDecodeError.corrupt`.
struct FileCursor {
    let fd: Int32
    let end: Int
    var offset = 0
    private var buffer: [UInt8] = []
    private var bufferStart = 0

    init(fd: Int32, end: Int) {
        self.fd = fd
        self.end = end
    }

    mutating func bytes(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, offset >= 0, n <= end - offset else { throw OwnDecodeError.corrupt }
        if offset < bufferStart || offset + n > bufferStart + buffer.count {
            bufferStart = offset
            buffer = try FileRead.bytes(fd, offset, min(max(n, 1 << 16), end - offset))
        }
        defer { offset += n }
        let i = offset - bufferStart
        return buffer[i ..< i + n]
    }

    /// Big-endian, unsigned.
    mutating func int(_ n: Int) throws -> Int { try bytes(n).reduce(0) { $0 << 8 | Int($1) } }
    mutating func int32() throws -> Int { Int(Int32(truncatingIfNeeded: try int(4))) }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= end - offset else { throw OwnDecodeError.corrupt }
        offset += n
    }

    /// Reads a `size`-byte length; the offset that many bytes after it, checked against the end.
    mutating func lengthEnd(_ size: Int) throws -> Int {
        let length = try int(size)
        guard length >= 0, length <= end - offset else { throw OwnDecodeError.corrupt }
        return offset + length
    }

    mutating func string(_ n: Int) throws -> String { String(decoding: try bytes(n), as: UTF8.self) }

    /// Tagged blocks ("8BIM"/"8B64", key, length, data) up to `limit`; zero padding between blocks is skipped.
    mutating func blocks(until limit: Int, version: Int) throws -> [String: Data] {
        var blocks: [String: Data] = [:]
        while limit - offset >= 12 {
            if try bytes(1).first == 0 { continue }
            offset -= 1
            let signature = try string(4)
            guard signature == "8BIM" || signature == "8B64" else { throw OwnDecodeError.corrupt }
            let key = try string(4)
            let length = try int(version == 2 && PSDLayers.longKeys.contains(key) ? 8 : 4)
            guard length <= limit - offset else { throw OwnDecodeError.corrupt }
            if PSDLayers.unreadKeys.contains(key) { try skip(length) } else { blocks[key] = Data(try bytes(length)) }
        }
        offset = max(offset, limit)
        return blocks
    }
}

/// One layer record, before the tree is built.
struct Record {
    var channelLengths: [(Int, Int)] = []
    var source = PSDChannelSource()
    let fields: (name: String, rect: PSDRect, blend: String, opacity: UInt8, clipped: Bool, visible: Bool,
                 mask: (rect: PSDRect, defaultColour: UInt8, flags: UInt8, channel: Int, density: UInt8, feather: Double)?,
                 vectorDensity: UInt8, vectorFeather: Double, blendIf: PSDBlendIf?, blocks: [String: Data])

    init(_ r: inout FileCursor, version: Int, end: Int) throws {
        let rect = try Self.rect(&r)
        for _ in 0..<(try r.int(2)) {
            let id = Int(Int16(truncatingIfNeeded: try r.int(2)))
            channelLengths.append((id, try r.int(version == 1 ? 4 : 8)))
        }
        guard try r.string(4) == "8BIM" else { throw OwnDecodeError.corrupt }
        let blend = try r.string(4)
        let opacity = UInt8(try r.int(1)), clipping = try r.int(1), flags = try r.int(1)
        try r.skip(1)
        let extraEnd = try r.lengthEnd(4)
        guard extraEnd <= end else { throw OwnDecodeError.corrupt }

        let maskEnd = try r.lengthEnd(4)
        var mask: (rect: PSDRect, defaultColour: UInt8, flags: UInt8, channel: Int, density: UInt8, feather: Double)?
        var vectorDensity: UInt8 = 255, vectorFeather = 0.0, rendered = false
        if maskEnd - r.offset >= 18 {
            let maskRect = try Self.rect(&r)
            let colour = UInt8(try r.int(1)), maskFlags = UInt8(try r.int(1))
            var user = (rect: maskRect, colour: colour, flags: maskFlags, channel: -2)
            // The user mask's own flags, colour and rectangle when the first ones hold a vector mask's rendering;
            // the parameters follow them.
            let real = maskEnd - r.offset >= 18 && channelLengths.contains(where: { $0.0 == -3 })
            if real {
                let realFlags = UInt8(try r.int(1)), realColour = UInt8(try r.int(1))
                user = (try Self.rect(&r), realColour, realFlags, -3)
            }
            var density: UInt8 = 255, feather = 0.0
            if maskFlags & 16 != 0, r.offset < maskEnd {
                let parameters = try r.int(1)
                if parameters & 1 != 0 { density = UInt8(try r.int(1)) }
                if parameters & 2 != 0 { feather = Double(bitPattern: UInt64(bitPattern: Int64(try r.int(8)))) }
                if parameters & 4 != 0 { vectorDensity = UInt8(try r.int(1)) }
                if parameters & 8 != 0 { vectorFeather = Double(bitPattern: UInt64(bitPattern: Int64(try r.int(8)))) }
            }
            // A feather past 1,000 px (Photoshop's limit) or not a number is damage.
            guard [feather, vectorFeather].allSatisfy({ $0.isFinite && (0...1000).contains($0) }) else { throw OwnDecodeError.corrupt }
            mask = (user.rect, user.colour, user.flags, user.channel, density, feather)
            rendered = !real && maskFlags & 8 != 0
        }
        guard maskEnd <= extraEnd else { throw OwnDecodeError.corrupt }
        r.offset = maskEnd

        let rangesEnd = try r.lengthEnd(4)
        guard rangesEnd <= extraEnd else { throw OwnDecodeError.corrupt }
        let ranges = try r.bytes(rangesEnd - r.offset)
        var blendIf: PSDBlendIf?
        if ranges.count >= 32, !ranges.prefix(32).enumerated().allSatisfy({ $0.element == ($0.offset % 4 < 2 ? 0 : 255) }) {
            let b = Array(ranges.prefix(32))
            func range(_ k: Int) -> PSDBlendIf.Range { (Array(b[k * 8 ..< k * 8 + 4]), Array(b[k * 8 + 4 ..< k * 8 + 8])) }
            blendIf = PSDBlendIf(gray: range(0), red: range(1), green: range(2), blue: range(3))
        }
        let nameLength = try r.int(1)
        let name = String(decoding: try r.bytes(nameLength), as: UTF8.self)
        try r.skip((4 - (1 + nameLength) % 4) % 4)
        guard r.offset <= extraEnd else { throw OwnDecodeError.corrupt }
        let blocks = try r.blocks(until: extraEnd, version: version)
        r.offset = extraEnd
        // Without a real one, a mask flagged as rendered from other data is the vector mask's, which draws from vmsk.
        if rendered, blocks["vmsk"] ?? blocks["vsms"] != nil { mask = nil }
        fields = (name, rect, blend, opacity, clipping != 0, flags & 2 == 0, mask, vectorDensity, vectorFeather, blendIf, blocks)
    }

    /// A layer or mask rectangle, at most 2^24 per side.
    static func rect(_ r: inout FileCursor) throws -> PSDRect {
        let rect = (top: try r.int32(), left: try r.int32(), bottom: try r.int32(), right: try r.int32())
        guard rect.bottom >= rect.top, rect.right >= rect.left,
              rect.bottom - rect.top <= 1 << 24, rect.right - rect.left <= 1 << 24 else { throw OwnDecodeError.corrupt }
        return rect
    }

    var layer: PSDLayer {
        let l = fields
        let mask = l.mask.map {
            PSDMask(rect: $0.rect, defaultColour: $0.defaultColour, disabled: $0.flags & 2 != 0, relative: $0.flags & 1 != 0,
                    density: $0.density, feather: $0.feather, channel: $0.channel, source: source)
        }
        return PSDLayer(name: l.name, rect: l.rect, blend: l.blend, opacity: l.opacity, fill: l.blocks["iOpa"]?.first ?? 255,
                        clipped: l.clipped, visible: l.visible, mask: mask, blendIf: l.blendIf, vectorDensity: l.vectorDensity,
                        vectorFeather: l.vectorFeather,
                        blocks: l.blocks, source: source)
    }
}

/// A zip channel's rows, inflated in order as they're asked for through about 1 MB of the stream and of rows at a
/// time, so a layer far larger than the canvas or the decode holds neither its whole stream nor its whole plane.
/// Asking for rows above the last ones starts the stream again.
final class ZipRows: @unchecked Sendable {  // `PSDChannelSource.reading` hands each to one thread at a time
    private let fd: Int32, offset: Int, length: Int, width: Int, predicted: Bool
    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private let input = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 1 << 18)
    private var live = false, taken = 0, row = 0

    init(fd: Int32, offset: Int, length: Int, width: Int, predicted: Bool) throws {
        (self.fd, self.offset, self.length, self.width, self.predicted) = (fd, offset, length, width, predicted)
        try Inflate.zlibHeader(try FileRead.bytes(fd, offset, 2)[...])
    }

    deinit {
        if live { compression_stream_destroy(stream) }
        stream.deallocate()
        input.deallocate()
    }

    /// Rows `rows` of the stream's plane, columns `columns` of each, into `out`.
    func rows(_ rows: Range<Int>, _ columns: Range<Int>, into out: UnsafeMutablePointer<UInt8>) throws {
        if !live || rows.lowerBound < row {
            if live { compression_stream_destroy(stream) }
            live = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
            guard live else { throw OwnDecodeError.corrupt }
            (taken, row) = (2, 0)
            stream.pointee.src_size = 0
        }
        let chunk = max(1, min((1 << 20) / width, rows.upperBound - row))
        var scratch = [UInt8](repeating: 0, count: chunk * width)
        PSDChannelSource.held(scratch.count)
        try scratch.withUnsafeMutableBufferPointer { scratch in
            let s = scratch.baseAddress!
            while row < rows.upperBound {
                let n = min(chunk, rows.upperBound - row)
                try fill(s, n * width)
                for i in min(n, max(0, rows.lowerBound - row)) ..< n {  // a chunk wholly above `rows` is only inflated
                    let at = s + i * width
                    if predicted { for x in 1 ..< columns.upperBound { at[x] &+= at[x - 1] } }
                    (out + (row + i - rows.lowerBound) * columns.count).update(from: at + columns.lowerBound, count: columns.count)
                }
                row += n
            }
        }
    }

    /// The next `count` bytes of the plane into `dst`; a stream that ends or breaks before them throws.
    private func fill(_ dst: UnsafeMutablePointer<UInt8>, _ count: Int) throws {
        stream.pointee.dst_ptr = dst
        stream.pointee.dst_size = count
        while stream.pointee.dst_size > 0 {
            if stream.pointee.src_size == 0, taken < length {
                let n = min(input.count, length - taken)
                try FileRead.read(fd, offset + taken, n, into: input.baseAddress!)
                PSDChannelSource.held(n)
                taken += n
                stream.pointee.src_ptr = UnsafePointer(input.baseAddress!)
                stream.pointee.src_size = n
            }
            let before = (stream.pointee.src_size, stream.pointee.dst_size)
            let flags = taken == length ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(stream, flags)
            guard status != COMPRESSION_STATUS_ERROR, status != COMPRESSION_STATUS_END || stream.pointee.dst_size == 0,
                  before != (stream.pointee.src_size, stream.pointee.dst_size) || stream.pointee.src_size == 0 && taken < length
            else { throw OwnDecodeError.corrupt }
        }
    }
}
