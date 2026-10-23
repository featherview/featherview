import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

/// Builds Paint.NET files the way the samples are laid out: `PDN3`, XML header, `00 01`, NRBF graph,
/// then each deferred MemoryBlock as gzip chunks.
struct PDNBuilder {
    struct Layer {
        var pixels: RGBAImage
        var visible = true
        var opacity: UInt8 = 255
        var extraStride = 0
        /// Bytes past the last row, counted in `length64`.
        var extraLength = 0
        /// Surface size written to the graph instead of the pixels' size (the block keeps the real pixels).
        var claimedSize: (width: Int, height: Int)?
    }

    typealias Chunk = (index: Int, raw: [UInt8])

    var width: Int
    var height: Int
    var layers: [Layer]
    var thumbnail: RGBAImage?
    /// Raw PNG for `<thumb>`, used instead of `thumbnail`.
    var thumbnailPNG: Data?
    var chunkSize = 16
    /// Rewrites one block's chunks before they're gzipped (reorder, drop, duplicate, replace).
    var chunks: (_ layer: Int, _ chunks: [Chunk]) -> [Chunk] = { $1 }


    static func png(_ image: RGBAImage) -> Data { Fixtures.encoded(image.makeCGImage()!, as: .png) }

    func xml() -> [UInt8] {
        let thumb = (thumbnailPNG ?? thumbnail.map(Self.png)).map { #"<custom><thumb png=""# + $0.base64EncodedString() + #"" /></custom>"# } ?? ""
        return Array(#"<pdnImage width="\#(width)" height="\#(height)" layers="\#(layers.count)" savedWithVersion="5.9.0.0">"#.utf8)
            + Array(thumb.utf8) + Array("</pdnImage>".utf8)
    }

    func graph() -> [UInt8] {
        var w = NRBFBytes()
        w.header(root: 1); w.library(2, "PaintDotNet.Data")
        w.classRecord(id: 1, name: "PaintDotNet.Document", members: [
            ("layers", .reference(2, className: "PaintDotNet.LayerList")), ("width", .int32(width)), ("height", .int32(height)),
        ])
        w.classRecord(id: 2, name: "PaintDotNet.LayerList", members: [
            ("parent", .reference(1, className: "PaintDotNet.Document")),
            ("ArrayList+_items", .objectArray(3)), ("ArrayList+_size", .int32(layers.count)),
        ])
        w.objectArray(id: 3, references: layers.indices.map { 10 + $0 * 10 }, nulls: 2)  // ArrayList keeps spare slots
        for (i, layer) in layers.enumerated() {
            let id = 10 + i * 10
            w.classRecord(id: id, name: "PaintDotNet.BitmapLayer", members: [
                ("properties", .null), ("surface", .reference(id + 2, className: "PaintDotNet.Surface")),
                ("Layer+width", .int32(layer.pixels.width)), ("Layer+height", .int32(layer.pixels.height)),
                ("Layer+properties", .reference(id + 1, className: "PaintDotNet.Layer+LayerProperties")),
            ])
            w.classRecord(id: id + 1, name: "PaintDotNet.Layer+LayerProperties", members: [
                ("name", .string(id: id + 5, "Layer \(i)")), ("visible", .bool(layer.visible)),
                ("isBackground", .bool(i == 0)), ("opacity", .byte(layer.opacity)),
            ])
            let (sw, sh) = layer.claimedSize ?? (layer.pixels.width, layer.pixels.height)
            w.classRecord(id: id + 2, name: "PaintDotNet.Surface", members: [
                ("width", .int32(sw)), ("height", .int32(sh)), ("stride", .int32(sw * 4 + layer.extraStride)),
                ("scan0", .reference(id + 3, className: "PaintDotNet.MemoryBlock")),
            ])
            w.classRecord(id: id + 3, name: "PaintDotNet.MemoryBlock", members: [
                ("length64", .int64(layer.claimedSize.map { $0.width * 4 * $0.height } ?? blockBytes(layer).count)), ("hasParent", .bool(false)), ("deferred", .bool(true)),
            ])
        }
        w.end()
        return w.bytes
    }

    /// BGRA rows, `stride` apart, the padding filled with junk.
    func blockBytes(_ layer: Layer) -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<layer.pixels.height {
            for x in 0..<layer.pixels.width {
                let p = layer.pixels[x, y]
                out += [p.b, p.g, p.r, p.a]
            }
            out += [UInt8](repeating: 0xEE, count: layer.extraStride)
        }
        return out + [UInt8](repeating: 0xEE, count: layer.extraLength)
    }

    func block(_ i: Int) -> [UInt8] {
        let bytes = blockBytes(layers[i])
        let raw: [Chunk] = stride(from: 0, to: bytes.count, by: chunkSize).enumerated().map { index, start in
            (index, Array(bytes[start..<min(start + chunkSize, bytes.count)]))
        }
        return [0] + Fixtures.be32(chunkSize) + chunks(i, raw).flatMap { chunk -> [UInt8] in
            let packed = InflateTests.gzip(chunk.raw)
            return Fixtures.be32(chunk.index) + Fixtures.be32(packed.count) + packed
        }
    }

    var bytes: [UInt8] {
        let header = xml()
        return Array("PDN3".utf8) + [UInt8(header.count & 0xFF), UInt8(header.count >> 8 & 0xFF), UInt8(header.count >> 16)]
            + header + [0x00, 0x01] + graph() + layers.indices.flatMap(block)
    }

    var data: Data { Data(bytes) }
}

@Suite struct PDNDecoderTests {
    static let red = Fixtures.solid(4, 3, (255, 0, 0, 255))

    /// Blue on the left half, transparent on the right.
    static var halfBlue: RGBAImage {
        var image = Fixtures.solid(4, 3, (0, 0, 0, 0))
        for y in 0..<3 { for x in 0..<2 { image[x, y] = (0, 0, 255, 255) } }
        return image
    }

    static func builder(_ layers: [PDNBuilder.Layer]) -> PDNBuilder { PDNBuilder(width: 4, height: 3, layers: layers) }

    @Test func sizeFromXMLHeader() throws {
        var b = Self.builder([.init(pixels: Self.red)])
        b.width = 4; b.height = 3
        #expect(try PDNDecoder.size(b.data) == (4, 3))
        // Only the header is needed: the body can be missing.
        #expect(try PDNDecoder.size(b.data.prefix(7 + b.xml().count)) == (4, 3))
    }

    @Test func singleLayerDecodes() throws {
        let image = try PDNDecoder.decode(Self.builder([.init(pixels: Self.red)]).data)
        #expect(image == Self.red)
    }

    @Test func usesCanvasSizedThumbnail() throws {
        var b = Self.builder([.init(pixels: Self.red)])
        b.thumbnail = Fixtures.solid(4, 3, (0, 255, 0, 255))
        #expect(try PDNDecoder.decode(b.data)[1, 1] == (0, 255, 0, 255))
    }

    @Test func ignoresSmallThumbnailAndUsesLayers() throws {
        var b = Self.builder([.init(pixels: Self.red)])
        b.thumbnail = Fixtures.solid(2, 1, (0, 255, 0, 255))
        #expect(try PDNDecoder.decode(b.data) == Self.red)
    }

    @Test func hugeThumbnailIsNotDecoded() throws {
        // A 10,000 × 10,000 1-bit PNG: tiny compressed, 400 MB as RGBA. Its size alone rules it out.
        let side = 10_000, rowBytes = side / 8
        let provider = CGDataProvider(data: Data(count: rowBytes * side) as CFData)!
        let gray = CGImage(width: side, height: side, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        var b = Self.builder([.init(pixels: Self.red)])
        b.thumbnailPNG = Fixtures.encoded(gray, as: .png)
        let start = ContinuousClock.now
        #expect(try PDNDecoder.decode(b.data) == Self.red)
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }

    @Test func twoLayersBottomFirst() throws {
        let image = try PDNDecoder.decode(Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue)]).data)
        #expect(image[0, 0] == (0, 0, 255, 255))
        #expect(image[3, 2] == (255, 0, 0, 255))
    }

    @Test func hiddenLayerIsSkipped() throws {
        let image = try PDNDecoder.decode(Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue, visible: false)]).data)
        #expect(image == Self.red)
    }

    @Test func layerOpacity() throws {
        let image = try PDNDecoder.decode(Self.builder([.init(pixels: Self.red, opacity: 128)]).data)
        #expect(image[2, 1] == (255, 0, 0, 128))
    }

    @Test func straightAlphaIsKept() throws {
        let image = try PDNDecoder.decode(Self.builder([.init(pixels: Fixtures.solid(4, 3, (200, 100, 50, 64)))]).data)
        #expect(image[0, 0] == (200, 100, 50, 64))
    }

    @Test func chunksInAnyOrder() throws {
        var b = Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue)])
        b.chunks = { _, chunks in chunks.reversed() }
        #expect(try PDNDecoder.decode(b.data) == PDNDecoder.decode(Self.builder(b.layers).data))
    }

    @Test func missingChunkThrows() {
        var b = Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue)])
        b.chunks = { layer, chunks in layer == 0 ? Array(chunks.dropFirst()) : chunks }
        #expect(throws: OwnDecodeError.self) { try PDNDecoder.decode(b.data) }
        b.chunks = { layer, chunks in layer == 1 ? Array(chunks.dropLast()) : chunks }
        #expect(throws: OwnDecodeError.truncated) { try PDNDecoder.decode(b.data) }
    }

    @Test func duplicateChunkThrows() {
        var b = Self.builder([.init(pixels: Self.red)])
        b.chunks = { _, chunks in [chunks[0], chunks[0]] + chunks.dropFirst(2) }
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(b.data) }
    }

    @Test func chunkIndexPastTheEndThrows() {
        var b = Self.builder([.init(pixels: Self.red)])
        b.chunks = { _, chunks in [(1000, chunks[0].raw)] + chunks.dropFirst() }
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(b.data) }
    }

    @Test func chunkBombThrows() {
        var b = Self.builder([.init(pixels: Self.red)])
        b.chunks = { _, chunks in [(0, [UInt8](repeating: 0, count: 1 << 20))] + chunks.dropFirst() }
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(b.data) }
    }

    @Test func strideLargerThanRow() throws {
        var b = Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue, extraStride: 8)])
        b.chunkSize = 7  // chunk edges fall inside pixels
        let image = try PDNDecoder.decode(b.data)
        #expect(image[0, 2] == (0, 0, 255, 255) && image[3, 2] == (255, 0, 0, 255))
    }

    @Test func truncatedAtEveryLengthThrows() {
        let bytes = Self.builder([.init(pixels: Self.red), .init(pixels: Self.halfBlue)]).bytes
        #expect(throws: Never.self) { try PDNDecoder.decode(Data(bytes)) }
        for length in 0..<bytes.count {
            #expect(throws: OwnDecodeError.self, "\(length)") { try PDNDecoder.decode(Data(bytes.prefix(length))) }
        }
    }

    @Test func hugeCanvasThrows() {
        var b = Self.builder([.init(pixels: Self.red)])
        b.width = 70000
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.size(b.data) }
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(b.data) }
    }

    @Test func hugeLayerThrows() {
        // A canvas past the pixel cap, or a surface that doesn't match the canvas, is refused before allocating.
        var b = Self.builder([.init(pixels: Self.red)])
        b.width = 60000; b.height = 60000
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(b.data) }
        var small = Self.builder([.init(pixels: Fixtures.solid(2, 2, (1, 2, 3, 255)))])
        small.width = 4; small.height = 3
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(small.data) }
    }

    @Test func noLayersThrows() {
        #expect(throws: OwnDecodeError.self) { try PDNDecoder.decode(Self.builder([]).data) }
        // A gigabyte canvas from a 364-byte file is refused before allocating it.
        let start = ContinuousClock.now
        #expect(throws: OwnDecodeError.self) { _ = try PDNDecoder.decode(PDNBuilder(width: 16384, height: 16384, layers: []).data) }
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }

    @Test func layerWithTooLittleDataThrowsBeforeAllocating() {
        for visible in [true, false] {
            var b = PDNBuilder(width: 16384, height: 16384, layers: [.init(pixels: Self.red, visible: visible, claimedSize: (16384, 16384))])
            b.chunkSize = Int(Int32.max)
            let start = ContinuousClock.now
            #expect(throws: OwnDecodeError.self) { _ = try PDNDecoder.decode(b.data) }
            #expect(ContinuousClock.now - start < .milliseconds(200))
        }
    }

    @Test func blockLengthMustMatchSurface() {
        // Paint.NET writes exactly stride × height; more would let a tiny layer inflate gigabytes.
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(Self.builder([.init(pixels: Self.red, extraLength: 16)]).data) }
        #expect(throws: OwnDecodeError.corrupt) { try PDNDecoder.decode(Self.builder([.init(pixels: Self.red, extraStride: 1000)]).data) }
    }

    @Test func olderBodyIsUnsupported() {
        var bytes = Self.builder([.init(pixels: Self.red)]).bytes
        let headerEnd = 7 + Self.builder([.init(pixels: Self.red)]).xml().count
        bytes[headerEnd + 1] = 0x02
        #expect(throws: OwnDecodeError.unsupported) { try PDNDecoder.decode(Data(bytes)) }
    }

    @Test func notPDNIsNotThisFormat() {
        let data = Data(Array("\u{89}PNG\r\n\u{1A}\n0000000000".utf8))
        #expect(throws: OwnDecodeError.notThisFormat) { try PDNDecoder.size(data) }
        #expect(throws: OwnDecodeError.notThisFormat) { try PDNDecoder.decode(data) }
    }

    // MARK: Sample corpus (opt-in: FEATHERVIEW_SAMPLES)

    static func load(_ url: URL) throws -> RGBAImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap(RGBAImage.init))
    }

    static func scaled(_ image: RGBAImage, width: Int, height: Int) throws -> RGBAImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(try #require(image.makeCGImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage().flatMap(RGBAImage.init))
    }

    @Test(.enabled(if: SampleCorpus.isAvailable)) func pdnCorpusMatchesReferences() throws {
        let folder = try #require(SampleCorpus.root).appendingPathComponent("pdn")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pdn" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 10)
        // Files with visible layers in other blend modes (XOR, Overlay, Additive), which we draw as normal.
        let otherBlendModes: Set = ["pypdn_FlattenBlendTest.pdn", "opengfx2_arctic_groundtiles_snowtransition_32bpp_old2.pdn",
                                    "pypdn_Untitled3.pdn"]
        for file in files {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let image = try PDNDecoder.decode(data)
            #expect(try PDNDecoder.size(data) == (image.width, image.height), "\(file.lastPathComponent)")
            let reference = SampleCorpus.reference(for: file)
            let named = file.deletingPathExtension().lastPathComponent + ".png"
            let full = reference.deletingLastPathComponent().appendingPathComponent(named)
            if FileManager.default.fileExists(atPath: full.path) {
                let difference = SampleCorpus.difference(image, try Self.load(full))
                #expect(difference < 3, "\(file.lastPathComponent): \(difference)")
            }
            guard !otherBlendModes.contains(file.lastPathComponent) else { continue }
            let thumb = try Self.load(reference.deletingPathExtension().appendingPathExtension("thumb.png"))
            let difference = SampleCorpus.difference(try Self.scaled(image, width: thumb.width, height: thumb.height), thumb)
            // < 7, not 6: the 34 px tall explosion strip's 1 px white grid lines resample differently (6.2).
            #expect(difference < 7, "\(file.lastPathComponent) vs thumbnail: \(difference)")
        }
    }
}
