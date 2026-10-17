import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

/// Writes PaintShop Pro files byte by byte: header, attributes, optional palette and composite bank, layer bank.
struct PSPBuilder {
    struct Layer {
        var pixels: RGBAImage                 // the saved rectangle's pixels
        var x = 0, y = 0                      // image rectangle origin on the canvas
        var savedX = 0, savedY = 0            // saved rectangle inside the image rectangle
        var opacity: UInt8 = 255
        var visible = true
        var type: UInt8 = 1
        var hasTransparency = true
        var samples: [UInt8]? = nil           // one channel (paletted or greyscale) instead of red, green, blue
        var extraChannels: [[UInt8]] = []     // Channel blocks written after the layer's own
    }

    struct Composite {
        var pixels: RGBAImage
        var thumbnail = false
        var jpeg: [UInt8]? = nil
    }

    var major = 8
    var width: Int, height: Int
    var compression = 0
    var bitDepth = 24
    var greyscale = false
    var palette: [(UInt8, UInt8, UInt8)]? = nil
    var composites: [Composite] = []
    var layers: [Layer] = []
    /// Extra bytes at the end of every chunk ("expansion fields" a newer writer may add), and an unknown
    /// extension block on each raster layer.
    var expansion = 0

    static func le16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)] }
    static func le32(_ v: Int) -> [UInt8] { InflateTests.le32(v) }

    static func block(_ id: Int, _ body: [UInt8]) -> [UInt8] { [0x7E, 0x42, 0x4B, 0] + le16(id) + le32(body.count) + body }
    func chunk(_ fields: [UInt8]) -> [UInt8] { Self.le32(fields.count + 4 + expansion) + fields + [UInt8](repeating: 0xEE, count: expansion) }

    static func rle(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [], i = 0
        while i < bytes.count {
            var run = 1
            while i + run < bytes.count, run < 127, bytes[i + run] == bytes[i] { run += 1 }
            if run >= 3 { out += [UInt8(128 + run), bytes[i]]; i += run; continue }
            var literal = 1
            while i + literal < bytes.count, literal < 127,
                  !(i + literal + 2 < bytes.count && bytes[i + literal] == bytes[i + literal + 1]
                    && bytes[i + literal] == bytes[i + literal + 2]) { literal += 1 }
            out += [UInt8(literal)] + bytes[i..<i + literal]
            i += literal
        }
        return out
    }

    func compress(_ bytes: [UInt8], _ compression: Int) -> [UInt8] {
        switch compression {
        case 1: Self.rle(bytes)
        case 2: InflateTests.zlib(bytes)
        default: bytes
        }
    }

    func channel(_ bytes: [UInt8], bitmap: Int, channel: Int, compression: Int, stored: [UInt8]? = nil) -> [UInt8] {
        let content = stored ?? compress(bytes, compression)
        // The uncompressed-length field is a padded bitmap size in real files, so write something else on purpose.
        return Self.block(5, chunk(Self.le32(content.count) + Self.le32(bytes.count * 3 + 40) + Self.le16(bitmap) + Self.le16(channel)) + content)
    }

    func planes(_ image: RGBAImage) -> (r: [UInt8], g: [UInt8], b: [UInt8], a: [UInt8]) {
        let p = image.pixels
        return (stride(from: 0, to: p.count, by: 4).map { p[$0] }, stride(from: 1, to: p.count, by: 4).map { p[$0] },
                stride(from: 2, to: p.count, by: 4).map { p[$0] }, stride(from: 3, to: p.count, by: 4).map { p[$0] })
    }

    static func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [UInt8] { [x0, y0, x1, y1].flatMap { le32($0) } }

    func layerBlock(_ layer: Layer, stored: [UInt8]? = nil) -> [UInt8] {
        let w = layer.pixels.width, h = layer.pixels.height
        var info = Self.le16(5) + Array("Layer".utf8) + [layer.type]
        info += Self.rect(layer.x, layer.y, layer.x + layer.savedX + w, layer.y + layer.savedY + h)
        info += Self.rect(layer.savedX, layer.savedY, layer.savedX + w, layer.savedY + h)
        info += [layer.opacity, 0, layer.visible ? 1 : 0, 0, 0] + Self.rect(0, 0, 0, 0) + Self.rect(0, 0, 0, 0) + [0, 0, 0]
        info += Self.le16(5) + [UInt8](repeating: 0, count: 40)
        if major >= 5 { info += [0] + Self.le32(0) }  // highlight colour
        var channels: [[UInt8]] = []
        if let samples = layer.samples {
            channels.append(channel(samples, bitmap: 0, channel: 0, compression: compression, stored: stored))
        } else {
            let p = planes(layer.pixels)
            channels += [channel(p.r, bitmap: 0, channel: 1, compression: compression, stored: stored),
                         channel(p.g, bitmap: 0, channel: 2, compression: compression, stored: stored),
                         channel(p.b, bitmap: 0, channel: 3, compression: compression, stored: stored)]
        }
        if layer.hasTransparency {
            channels.append(channel(planes(layer.pixels).a, bitmap: 1, channel: 0, compression: compression, stored: stored))
        }
        channels += layer.extraChannels
        let extensionBlock = expansion > 0 ? Self.block(33, [1, 2, 3, 4]) : []
        let bitmaps = layer.hasTransparency ? 2 : 1
        return Self.block(4, chunk(info) + extensionBlock + chunk(Self.le16(bitmaps) + Self.le16(channels.count)) + channels.joined())
    }

    func compositeBank() -> [UInt8] {
        var attributes: [UInt8] = [], images: [UInt8] = []
        for c in composites {
            let isJPEG = c.jpeg != nil
            attributes += Self.block(17, chunk(Self.le32(c.pixels.width) + Self.le32(c.pixels.height) + Self.le16(24)
                                               + Self.le16(isJPEG ? 3 : compression) + Self.le16(1) + Self.le32(1 << 24)
                                               + Self.le16(c.thumbnail ? 1 : 0)))
            if let jpeg = c.jpeg {
                images += Self.block(18, chunk(Self.le32(jpeg.count) + Self.le32(c.pixels.pixels.count) + Self.le16(5)) + jpeg)
            } else {
                let p = planes(c.pixels)
                images += Self.block(9, chunk(Self.le16(2) + Self.le16(4))
                                     + channel(p.r, bitmap: 8, channel: 1, compression: compression)
                                     + channel(p.g, bitmap: 8, channel: 2, compression: compression)
                                     + channel(p.b, bitmap: 8, channel: 3, compression: compression)
                                     + channel(p.a, bitmap: 9, channel: 0, compression: compression))
            }
        }
        return Self.block(16, chunk(Self.le32(composites.count)) + attributes + images)
    }

    func header() -> [UInt8] {
        var signature = Array("Paint Shop Pro Image File\n\u{1A}".utf8)
        signature += [UInt8](repeating: 0, count: 32 - signature.count)
        let attributes = chunk(Self.le32(width) + Self.le32(height) + [UInt8](repeating: 0, count: 8) + [1]
                               + Self.le16(compression) + Self.le16(bitDepth) + Self.le16(1) + Self.le32(1 << min(bitDepth, 24))
                               + [greyscale ? 1 : 0] + Self.le32(0) + Self.le32(0) + Self.le16(layers.count) + Self.le32(0))
        return signature + Self.le16(major) + Self.le16(0) + Self.block(0, attributes)
    }

    func bytes(storedChannel: [UInt8]? = nil) -> [UInt8] {
        var out = header()
        if !composites.isEmpty { out += compositeBank() }
        if let palette {
            out += Self.block(2, chunk(Self.le32(palette.count)) + palette.flatMap { [$0.0, $0.1, $0.2, 0] })
        }
        out += Self.block(3, layers.map { layerBlock($0, stored: storedChannel) }.joined().map { $0 })
        return out
    }

    var data: Data { Data(bytes()) }
}

@Suite struct PSPDecoderTests {
    static func solid(_ width: Int, _ height: Int, _ color: (UInt8, UInt8, UInt8, UInt8)) -> RGBAImage {
        RGBAImage(width: width, height: height, pixels: (0..<width * height).flatMap { _ in [color.0, color.1, color.2, color.3] })
    }

    /// Distinct colours per pixel, partly transparent, so channel mix-ups and offsets show.
    static func pattern(_ width: Int, _ height: Int) -> RGBAImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            image[x, y] = (UInt8(x * 13 % 256), UInt8(y * 29 % 256), UInt8((x + y) * 7 % 256), x % 3 == 0 ? 128 : 255)
        } }
        return image
    }

    static func background(_ width: Int, _ height: Int, _ color: (UInt8, UInt8, UInt8)) -> PSPBuilder.Layer {
        PSPBuilder.Layer(pixels: solid(width, height, (color.0, color.1, color.2, 255)), hasTransparency: false)
    }

    @Test func usesFullSizeCompositeWhenStored() throws {
        var file = PSPBuilder(width: 4, height: 3)
        file.composites = [.init(pixels: Self.solid(2, 2, (9, 9, 9, 255)), thumbnail: true), .init(pixels: Self.pattern(4, 3))]
        file.layers = [Self.background(4, 3, (255, 0, 0))]
        #expect(try PSPDecoder.decode(file.data) == Self.pattern(4, 3))
    }

    @Test func ignoresThumbnailOnlyBankAndUsesLayers() throws {
        var file = PSPBuilder(width: 4, height: 3)
        file.composites = [.init(pixels: Self.solid(4, 3, (9, 9, 9, 255)), thumbnail: true)]  // full size, but a thumbnail
        file.layers = [Self.background(4, 3, (255, 0, 0))]
        #expect(try PSPDecoder.decode(file.data) == Self.solid(4, 3, (255, 0, 0, 255)))
    }

    @Test func jpegCompositeDecodesThroughImageIO() throws {
        let gray = Self.solid(8, 8, (128, 128, 128, 255))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let cgGray = try #require(gray.makeCGImage())
        CGImageDestinationAddImage(destination, cgGray, nil)
        #expect(CGImageDestinationFinalize(destination))
        var file = PSPBuilder(width: 8, height: 8)
        file.composites = [.init(pixels: gray, jpeg: [UInt8](output as Data))]
        file.layers = [Self.background(8, 8, (255, 0, 0))]
        let image = try PSPDecoder.decode(file.data)
        #expect(image.width == 8 && abs(Int(image[3, 3].r) - 128) <= 3 && image[3, 3].a == 255)
    }

    @Test func twoLayersWithOpacity() throws {
        var file = PSPBuilder(width: 4, height: 3)
        let top = Self.pattern(4, 3)
        file.layers = [Self.background(4, 3, (0, 0, 255)), .init(pixels: top, opacity: 128)]
        var canvas = try LayerCanvas(width: 4, height: 3)
        canvas.draw(Self.solid(4, 3, (0, 0, 255, 255)), x: 0, y: 0, opacity: 1)
        canvas.draw(top, x: 0, y: 0, opacity: 128.0 / 255)
        #expect(try PSPDecoder.decode(file.data) == canvas.image)
    }

    @Test func hiddenLayerIsSkipped() throws {
        var file = PSPBuilder(width: 4, height: 3)
        file.layers = [Self.background(4, 3, (0, 0, 255)), .init(pixels: Self.solid(4, 3, (255, 0, 0, 255)), visible: false)]
        #expect(try PSPDecoder.decode(file.data) == Self.solid(4, 3, (0, 0, 255, 255)))
    }

    @Test func layerRectangleOffset() throws {
        var file = PSPBuilder(width: 6, height: 5)
        let small = Self.solid(2, 2, (255, 0, 0, 255))
        file.layers = [Self.background(6, 5, (0, 0, 255)), .init(pixels: small, x: 1, y: 1, savedX: 2, savedY: 1)]
        let image = try PSPDecoder.decode(file.data)
        #expect(image[3, 2] == (255, 0, 0, 255) && image[4, 3] == (255, 0, 0, 255))
        #expect(image[2, 2] == (0, 0, 255, 255) && image[3, 1] == (0, 0, 255, 255) && image[5, 4] == (0, 0, 255, 255))
    }

    @Test func transparencyChannelIsAlpha() throws {
        var file = PSPBuilder(width: 4, height: 3)
        file.layers = [.init(pixels: Self.pattern(4, 3))]
        #expect(try PSPDecoder.decode(file.data) == Self.pattern(4, 3))
    }

    @Test func rleChannel() throws {
        var file = PSPBuilder(width: 70, height: 3)
        file.compression = 1
        var image = Self.pattern(70, 3)
        for x in 10..<60 { image[x, 1] = (5, 6, 7, 255) }  // long runs
        file.layers = [.init(pixels: image)]
        #expect(try PSPDecoder.decode(file.data) == image)
    }

    @Test func lz77Channel() throws {
        var file = PSPBuilder(width: 70, height: 3)
        file.compression = 2
        file.layers = [.init(pixels: Self.pattern(70, 3))]
        #expect(try PSPDecoder.decode(file.data) == Self.pattern(70, 3))
    }

    @Test func palettedLayer() throws {
        var file = PSPBuilder(width: 3, height: 1)
        file.bitDepth = 8
        file.palette = [(0, 0, 0), (255, 0, 0), (0, 255, 0)]
        file.layers = [.init(pixels: Self.solid(3, 1, (0, 0, 0, 255)), hasTransparency: false, samples: [2, 1, 0])]
        let image = try PSPDecoder.decode(file.data)
        #expect(image[0, 0] == (0, 255, 0, 255) && image[1, 0] == (255, 0, 0, 255) && image[2, 0] == (0, 0, 0, 255))
    }

    @Test func greyscale() throws {
        var file = PSPBuilder(width: 3, height: 1)
        file.bitDepth = 8
        file.greyscale = true
        file.layers = [.init(pixels: Self.solid(3, 1, (0, 0, 0, 255)), hasTransparency: false, samples: [10, 128, 250])]
        let image = try PSPDecoder.decode(file.data)
        #expect(image[0, 0] == (10, 10, 10, 255) && image[1, 0] == (128, 128, 128, 255) && image[2, 0] == (250, 250, 250, 255))
    }

    @Test func format8BlockChunkLengths() throws {
        // Every chunk is longer than the fields we read, and each layer has an extension block before its bitmaps.
        var file = PSPBuilder(width: 4, height: 3)
        file.expansion = 6
        file.layers = [Self.background(4, 3, (0, 0, 255)), .init(pixels: Self.pattern(2, 2), x: 1, y: 1)]
        var canvas = try LayerCanvas(width: 4, height: 3)
        canvas.draw(Self.solid(4, 3, (0, 0, 255, 255)), x: 0, y: 0, opacity: 1)
        canvas.draw(Self.pattern(2, 2), x: 1, y: 1, opacity: 1)
        #expect(try PSPDecoder.decode(file.data) == canvas.image)
        file.major = 4
        #expect(try PSPDecoder.decode(file.data) == canvas.image)
    }

    @Test func formatThreeIsUnsupported() {
        var file = PSPBuilder(width: 4, height: 3)
        file.major = 3
        file.layers = [Self.background(4, 3, (0, 0, 255))]
        #expect(throws: OwnDecodeError.unsupported) { try PSPDecoder.decode(file.data) }
    }

    @Test func sizeReadsHeaderOnly() throws {
        var file = PSPBuilder(width: 640, height: 480)
        file.layers = [Self.background(2, 2, (0, 0, 255))]
        #expect(try PSPDecoder.size(Data(file.header())) == (640, 480))
    }

    @Test func userMaskWithItsOwnRectangleIsIgnored() throws {
        var file = PSPBuilder(width: 4, height: 3)
        var layer = PSPBuilder.Layer(pixels: Self.pattern(4, 3))
        layer.extraChannels = [file.channel([255], bitmap: 2, channel: 0, compression: 0)]  // a 1 × 1 mask
        file.layers = [layer]
        #expect(try PSPDecoder.decode(file.data) == Self.pattern(4, 3))
    }

    // MARK: - Hostile input

    @Test func repeatedChannelIsNotDecodedAgain() throws {
        // A second red plane would cost another full plane (a bomb when repeated); it's skipped unread.
        var file = PSPBuilder(width: 4, height: 3)
        var layer = PSPBuilder.Layer(pixels: Self.pattern(4, 3))
        layer.extraChannels = [file.channel([1], bitmap: 0, channel: 1, compression: 0)]
        file.layers = [layer]
        #expect(try PSPDecoder.decode(file.data) == Self.pattern(4, 3))
    }

    static func smallTwoLayerFile() -> [UInt8] {
        var file = PSPBuilder(width: 4, height: 3)
        file.compression = 2
        file.layers = [Self.background(4, 3, (0, 0, 255)), .init(pixels: Self.pattern(2, 2), x: 1, y: 1)]
        return file.bytes()
    }

    @Test func truncatedAtEveryLengthThrows() throws {
        let bytes = Self.smallTwoLayerFile()
        _ = try PSPDecoder.decode(Data(bytes))
        for length in 0..<bytes.count {
            #expect(throws: OwnDecodeError.self, "\(length)") { try PSPDecoder.decode(Data(bytes[0..<length])) }
        }
    }

    @Test func blockLengthPastTheEndThrows() {
        var bytes = Self.smallTwoLayerFile()
        let layerBank = try! #require((36..<bytes.count - 6).first { bytes[$0..<$0 + 6] == [0x7E, 0x42, 0x4B, 0, 3, 0] })
        bytes.replaceSubrange(layerBank + 6..<layerBank + 10, with: PSPBuilder.le32(0x7FFF_FFF0))
        #expect(throws: OwnDecodeError.self) { try PSPDecoder.decode(Data(bytes)) }
    }

    @Test func hugeLayerThrows() {
        var file = PSPBuilder(width: 4, height: 3)
        file.layers = [.init(pixels: Self.solid(1, 1, (1, 2, 3, 255)), savedX: 0, savedY: 0)]
        var bytes = file.bytes()
        // Rewrite the saved rectangle's lower-right corner to 60,000 × 60,000.
        let saved = try! #require((0..<bytes.count - 16).last { Array(bytes[$0..<$0 + 16]) == PSPBuilder.rect(0, 0, 1, 1) })
        bytes.replaceSubrange(saved + 8..<saved + 16, with: PSPBuilder.le32(60000) + PSPBuilder.le32(60000))
        #expect(bytes.count < 1024)
        #expect(throws: OwnDecodeError.corrupt) { try PSPDecoder.decode(Data(bytes)) }
    }

    @Test(arguments: [0, 16]) func compositeBitDepthOtherThanTheKnownOnesThrows(depth: Int) throws {
        var file = PSPBuilder(width: 4, height: 3)
        file.composites = [.init(pixels: Self.pattern(4, 3))]
        var bytes = file.bytes()
        func block(_ id: UInt8) throws -> Int {
            try #require((0..<bytes.count - 6).first { bytes[$0..<$0 + 6] == [0x7E, 0x42, 0x4B, 0, id, 0] })
        }
        bytes.replaceSubrange(try block(17) + 22..<(try block(17)) + 24, with: PSPBuilder.le16(depth))
        // The red plane as a (bitmap 8, channel 0) one, the plane a non-24-bit composite is read from.
        bytes.replaceSubrange(try block(5) + 24..<(try block(5)) + 26, with: PSPBuilder.le16(0))
        #expect(throws: OwnDecodeError.corrupt) { try PSPDecoder.decode(Data(bytes)) }
    }

    @Test func lz77BombThrows() {
        var file = PSPBuilder(width: 4, height: 4)
        file.compression = 2
        file.layers = [.init(pixels: Self.solid(4, 4, (1, 2, 3, 255)))]
        let bomb = InflateTests.zlib([UInt8](repeating: 0, count: 100_000))
        #expect(throws: OwnDecodeError.corrupt) { try PSPDecoder.decode(Data(file.bytes(storedChannel: bomb))) }
    }

    @Test func notPSPIsNotThisFormat() {
        #expect(throws: OwnDecodeError.notThisFormat) { try PSPDecoder.decode(Data(repeating: 0x41, count: 200)) }
        #expect(throws: OwnDecodeError.notThisFormat) { try PSPDecoder.size(Data([1, 2, 3])) }
    }

    // MARK: - Sample corpus

    /// Their stored composite includes vector layers (the text on the button) that GIMP's flatten, the
    /// reference, leaves out; we show the composite, as PaintShop Pro saved it.
    static let composedWithVectorLayers: Set = ["stackview_GreenButton.pspimage", "stackview_HintUp.pspimage"]

    @Test(.enabled(if: SampleCorpus.isAvailable)) func pspCorpusMatchesReferences() throws {
        let folder = try #require(SampleCorpus.root).appendingPathComponent("psp")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["psp", "pspimage"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        for file in files {
            let image = try PSPDecoder.decode(Data(contentsOf: file, options: .mappedIfSafe))
            let source = try #require(CGImageSourceCreateWithURL(SampleCorpus.reference(for: file) as CFURL, nil))
            let cgReference = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let reference = try #require(RGBAImage(cgReference))
            let difference = SampleCorpus.difference(image, reference)
            print("PSP corpus \(file.lastPathComponent): \(image.width)×\(image.height), difference \(difference)")
            if Self.composedWithVectorLayers.contains(file.lastPathComponent) {
                #expect(image.width == reference.width && image.height == reference.height, "\(file.lastPathComponent)")
            } else {
                #expect(difference < 3, "\(file.lastPathComponent)")
            }
        }
    }
}
