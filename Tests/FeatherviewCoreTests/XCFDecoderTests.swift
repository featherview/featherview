import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

/// Writes XCF files byte by byte, as the spec lays them out: header, image properties, layer pointers
/// (topmost first), then each layer with its hierarchy, level and tiles.
struct XCFBuilder {
    struct Layer {
        var width: Int, height: Int
        /// 0 RGB, 1 RGBA, 2 gray, 3 gray + alpha, 4 indexed, 5 indexed + alpha
        var type = 1
        /// Row-major, all bytes of a pixel together (big-endian components), as the tiles store them.
        var pixels: [UInt8]
        var x = 0, y = 0
        var opacity: Int? = nil
        var floatOpacity: Float? = nil
        var visible = true
        /// Row-major, one component per pixel at the image precision.
        var mask: [UInt8]? = nil
        var applyMask: Bool? = nil
        var group = false
        var path: [Int]? = nil
    }

    struct Built {
        var bytes: [UInt8]
        var layerPointerSlots: [Int] = []
        var layerOffsets: [Int] = []
        var tilePointerSlots: [Int] = []
        var pointerSize: Int
    }

    var width: Int, height: Int
    var baseType = 0
    var version = 0
    var precision = 150
    var compression = 0
    var colormap: [UInt8]? = nil
    var extraProperties: [UInt8] = []
    var layers: [Layer] = []

    static func be16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
    static func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v) }
    static func be64(_ v: Int) -> [UInt8] { be32(v >> 32) + be32(v) }
    static func float(_ v: Float) -> [UInt8] { be32(Int(v.bitPattern)) }
    static func double(_ v: Double) -> [UInt8] { be64(Int(bitPattern: UInt(v.bitPattern))) }
    static func prop(_ type: Int, _ payload: [UInt8]) -> [UInt8] { be32(type) + be32(payload.count) + payload }
    static func string(_ s: String) -> [UInt8] { be32(s.utf8.count + 1) + Array(s.utf8) + [0] }

    /// XCF's RLE: per byte plane, runs of equal bytes and runs of literals, short and long forms.
    static func rle(_ tile: [UInt8], bpp: Int) -> [UInt8] {
        var out: [UInt8] = []
        for p in 0..<bpp {
            let plane = stride(from: p, to: tile.count, by: bpp).map { tile[$0] }
            var i = 0
            while i < plane.count {
                var run = 1
                while i + run < plane.count, plane[i + run] == plane[i] { run += 1 }
                if run >= 2 {
                    out += run <= 127 ? [UInt8(run - 1), plane[i]] : [127] + be16(run) + [plane[i]]
                    i += run
                    continue
                }
                var literal = 1
                while i + literal < plane.count,
                      i + literal + 1 >= plane.count || plane[i + literal] != plane[i + literal + 1] { literal += 1 }
                let bytes = Array(plane[i..<i + literal])
                out += literal <= 127 ? [UInt8(256 - literal)] + bytes : [128] + be16(literal) + bytes
                i += literal
            }
        }
        return out
    }

    func build() -> Built {
        let wide = version >= 11
        func pointer(_ v: Int) -> [UInt8] { wide ? Self.be64(v) : Self.be32(v) }
        var built = Built(bytes: [], pointerSize: wide ? 8 : 4)
        func patch(_ slot: Int, _ value: Int) {
            built.bytes.replaceSubrange(slot..<slot + built.pointerSize, with: pointer(value))
        }
        func slot() -> Int { defer { built.bytes += pointer(0) }; return built.bytes.count }

        func hierarchy(width: Int, height: Int, pixels: [UInt8]) {
            let bpp = pixels.count / (width * height)
            built.bytes += Self.be32(width) + Self.be32(height) + Self.be32(bpp)
            let level = slot()
            built.bytes += pointer(0)
            patch(level, built.bytes.count)
            built.bytes += Self.be32(width) + Self.be32(height)
            var tiles: [(slot: Int, bytes: [UInt8])] = []
            for ty in stride(from: 0, to: height, by: 64) {
                for tx in stride(from: 0, to: width, by: 64) {
                    var tile: [UInt8] = []
                    for y in ty..<min(ty + 64, height) {
                        let start = (y * width + tx) * bpp
                        tile += pixels[start..<start + (min(tx + 64, width) - tx) * bpp]
                    }
                    tiles.append((slot(), tile))
                }
            }
            built.tilePointerSlots += tiles.map(\.slot)
            built.bytes += pointer(0)
            for tile in tiles {
                patch(tile.slot, built.bytes.count)
                switch compression {
                case 1: built.bytes += Self.rle(tile.bytes, bpp: bpp)
                case 2: built.bytes += InflateTests.zlib(tile.bytes)
                default: built.bytes += tile.bytes
                }
            }
        }

        built.bytes = Array("gimp xcf ".utf8) + Array((version == 0 ? "file" : String(format: "v%03d", version)).utf8) + [0]
        built.bytes += Self.be32(width) + Self.be32(height) + Self.be32(baseType)
        if version >= 4 { built.bytes += Self.be32(precision) }
        if let colormap { built.bytes += Self.prop(1, Self.be32(colormap.count / 3) + colormap) }
        built.bytes += Self.prop(17, [UInt8(compression)]) + extraProperties + Self.prop(0, [])
        built.layerPointerSlots = layers.map { _ in slot() }
        built.bytes += pointer(0) + pointer(0)  // end of layers, no channels

        for (i, layer) in layers.enumerated() {
            patch(built.layerPointerSlots[i], built.bytes.count)
            built.layerOffsets.append(built.bytes.count)
            built.bytes += Self.be32(layer.width) + Self.be32(layer.height) + Self.be32(layer.type) + Self.string("Layer \(i)")
            built.bytes += Self.prop(8, Self.be32(layer.visible ? 1 : 0))
            if let o = layer.opacity { built.bytes += Self.prop(6, Self.be32(o)) }
            if let o = layer.floatOpacity { built.bytes += Self.prop(33, Self.float(o)) }
            built.bytes += Self.prop(15, Self.be32(layer.x) + Self.be32(layer.y))
            if let apply = layer.applyMask { built.bytes += Self.prop(11, Self.be32(apply ? 1 : 0)) }
            if layer.group { built.bytes += Self.prop(29, []) }
            if let path = layer.path { built.bytes += Self.prop(30, path.flatMap(Self.be32)) }
            built.bytes += Self.prop(7, Self.be32(28)) + Self.prop(0, [])
            let pixels = slot(), mask = slot()
            patch(pixels, built.bytes.count)
            hierarchy(width: layer.width, height: layer.height, pixels: layer.pixels)
            if let maskPixels = layer.mask {
                patch(mask, built.bytes.count)
                built.bytes += Self.be32(layer.width) + Self.be32(layer.height) + Self.string("Mask") + Self.prop(0, [])
                let h = slot()
                patch(h, built.bytes.count)
                hierarchy(width: layer.width, height: layer.height, pixels: maskPixels)
            }
        }
        return built
    }

    var data: Data { Data(build().bytes) }
}

@Suite struct XCFDecoderTests {
    typealias B = XCFBuilder

    static func solid(_ width: Int, _ height: Int, _ pixel: [UInt8]) -> [UInt8] {
        (0..<width * height).flatMap { _ in pixel }
    }

    /// 70 × 66 RGBA: two tile columns and rows (edge tiles 6 wide, 2 high), with long and short
    /// literal runs and long and short runs of equal bytes in the RLE planes.
    static func pattern(_ width: Int = 70, _ height: Int = 66) -> [UInt8] {
        (0..<height).flatMap { y in
            (0..<width).flatMap { x -> [UInt8] in
                [UInt8(truncatingIfNeeded: x * 3), UInt8(truncatingIfNeeded: y * 3),
                 x % 10 < 5 ? 9 : UInt8(truncatingIfNeeded: x * 7),
                 y < 20 || x < 35 ? 255 : 200]
            }
        }
    }

    static func close(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (UInt8, UInt8, UInt8, UInt8), within d: Int = 0) -> Bool {
        abs(Int(a.r) - Int(b.0)) <= d && abs(Int(a.g) - Int(b.1)) <= d && abs(Int(a.b) - Int(b.2)) <= d && abs(Int(a.a) - Int(b.3)) <= d
    }

    @Test func oneOpaqueRGBLayer() throws {
        var file = B(width: 3, height: 2)
        file.layers = [.init(width: 3, height: 2, type: 0,
                             pixels: [255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3, 4, 5, 6, 7, 8, 9])]
        let image = try XCFDecoder.decode(file.data)
        #expect(image.width == 3 && image.height == 2)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (0, 255, 0, 255) && image[2, 0] == (0, 0, 255, 255))
        #expect(image[0, 1] == (1, 2, 3, 255) && image[2, 1] == (7, 8, 9, 255))
        #expect(try XCFDecoder.size(file.data) == (3, 2))
    }

    func tiled(compression: Int) throws {
        var file = B(width: 70, height: 66, version: 11, compression: compression)
        file.layers = [.init(width: 70, height: 66, pixels: Self.pattern())]
        #expect(try XCFDecoder.decode(file.data) == RGBAImage(width: 70, height: 66, pixels: Self.pattern()))
    }

    @Test func rleTiles() throws { try tiled(compression: 1) }
    @Test func zlibTiles() throws { try tiled(compression: 2) }

    @Test func twoLayersWithOffsetAndOpacity() throws {
        let blue = Self.solid(4, 3, [0, 0, 255]), red = Self.solid(2, 2, [255, 0, 0, 255])
        var file = B(width: 4, height: 3, version: 11, compression: 1)
        file.layers = [.init(width: 2, height: 2, pixels: red, x: 2, y: 1, opacity: 127, floatOpacity: 0.5),
                       .init(width: 4, height: 3, type: 0, pixels: blue)]
        var canvas = try LayerCanvas(width: 4, height: 3)
        canvas.draw(RGBAImage(width: 4, height: 3, pixels: Self.solid(4, 3, [0, 0, 255, 255])), x: 0, y: 0, opacity: 1)
        canvas.draw(RGBAImage(width: 2, height: 2, pixels: red), x: 2, y: 1, opacity: 0.5)
        #expect(try XCFDecoder.decode(file.data) == canvas.image)
    }

    @Test func hiddenLayerIsSkipped() throws {
        var file = B(width: 2, height: 1)
        file.layers = [.init(width: 2, height: 1, pixels: Self.solid(2, 1, [255, 0, 0, 255]), visible: false),
                       .init(width: 2, height: 1, type: 0, pixels: Self.solid(2, 1, [0, 255, 0]))]
        #expect(try XCFDecoder.decode(file.data)[1, 0] == (0, 255, 0, 255))
    }

    @Test func grayWithAlpha() throws {
        var file = B(width: 2, height: 1, baseType: 1)
        file.layers = [.init(width: 2, height: 1, type: 3, pixels: [100, 255, 200, 128])]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[0, 0] == (100, 100, 100, 255) && image[1, 0] == (200, 200, 200, 128))
    }

    @Test func indexedWithAlphaThreshold() throws {
        var file = B(width: 3, height: 1, baseType: 2, version: 1, colormap: [10, 20, 30, 40, 50, 60])
        file.layers = [.init(width: 3, height: 1, type: 5, pixels: [0, 127, 1, 128, 0, 255])]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[0, 0].a == 0)
        #expect(image[1, 0] == (40, 50, 60, 255) && image[2, 0] == (10, 20, 30, 255))
    }

    @Test func appliedMaskMultipliesAlpha() throws {
        var file = B(width: 3, height: 1)
        file.layers = [.init(width: 3, height: 1, pixels: Self.solid(3, 1, [255, 0, 0, 255]), mask: [255, 128, 0], applyMask: true)]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0] == (255, 0, 0, 128) && image[2, 0].a == 0)
    }

    @Test func maskNotAppliedIsIgnored() throws {
        var file = B(width: 3, height: 1)
        file.layers = [.init(width: 3, height: 1, pixels: Self.solid(3, 1, [255, 0, 0, 255]), mask: [255, 128, 0], applyMask: false)]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[1, 0] == (255, 0, 0, 255) && image[2, 0] == (255, 0, 0, 255))
    }

    @Test func groupDrawsItsProjectionNotItsChildren() throws {
        var file = B(width: 2, height: 2, version: 3)
        file.layers = [.init(width: 2, height: 2, pixels: Self.solid(2, 2, [0, 255, 0, 255]), group: true, path: [0]),
                       .init(width: 2, height: 2, pixels: Self.solid(2, 2, [255, 0, 0, 255]), path: [0, 0]),
                       .init(width: 1, height: 1, pixels: [0, 0, 255, 255], path: [0, 1])]
        #expect(try XCFDecoder.decode(file.data) == RGBAImage(width: 2, height: 2, pixels: Self.solid(2, 2, [0, 255, 0, 255])))
    }

    @Test func negativeOffsetsAreClipped() throws {
        let pixels = (0..<16).flatMap { i -> [UInt8] in [UInt8(i), 0, 0, 255] }
        var file = B(width: 3, height: 3)
        file.layers = [.init(width: 4, height: 4, pixels: pixels, x: -2, y: -1)]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[0, 0] == (6, 0, 0, 255))   // layer pixel (2, 1)
        #expect(image[1, 2] == (15, 0, 0, 255))  // layer pixel (3, 3)
        #expect(image[2, 0].a == 0 && image[0, 2] == (14, 0, 0, 255))
    }

    @Test func sixteenBitGamma() throws {
        var file = B(width: 1, height: 1, version: 12, precision: 250)
        file.layers = [.init(width: 1, height: 1, pixels: B.be16(0xFFFF) + B.be16(0x8080) + B.be16(0) + B.be16(0xFFFF))]
        #expect(try XCFDecoder.decode(file.data)[0, 0] == (255, 128, 0, 255))
    }

    @Test func halfFloatLinear() throws {
        var file = B(width: 2, height: 1, version: 12, precision: 500)
        // 1.0, 0.5, a subnormal, 1.0 | 2.0 (clamps), -1.0 (clamps), 0.25, 0.5 alpha (not gamma-encoded)
        file.layers = [.init(width: 2, height: 1, pixels: [0x3C00, 0x3800, 0x0001, 0x3C00, 0x4000, 0xBC00, 0x3400, 0x3800].flatMap(B.be16))]
        let image = try XCFDecoder.decode(file.data)
        #expect(image[0, 0] == (255, 188, 0, 255))
        #expect(Self.close(image[1, 0], (255, 0, 137, 128), within: 1))
    }

    @Test func doubleGamma() throws {
        var file = B(width: 1, height: 1, version: 12, precision: 750)
        file.layers = [.init(width: 1, height: 1, pixels: [0.5, 1, 0.25, 1].flatMap(B.double))]
        #expect(try XCFDecoder.decode(file.data)[0, 0] == (128, 255, 64, 255))
    }

    @Test func linearLightLooksLikeGamma() throws {
        let values: [UInt8] = [0, 1, 10, 50, 128, 200, 254, 255]
        let colours: [[UInt8]] = values.map { v in [v, 255 - v, v / 2] }
        func linear(_ v: UInt8) -> Int {
            let c = Double(v) / 255
            return Int(((c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)) * 65535).rounded())
        }
        var gamma = B(width: values.count, height: 1, version: 12, precision: 150)
        gamma.layers = [.init(width: values.count, height: 1, type: 0, pixels: colours.flatMap { $0 })]
        var light = B(width: values.count, height: 1, version: 12, precision: 200)
        light.layers = [.init(width: values.count, height: 1, type: 0, pixels: colours.flatMap { $0.flatMap { B.be16(linear($0)) } })]
        let a = try XCFDecoder.decode(gamma.data), b = try XCFDecoder.decode(light.data)
        for x in values.indices { #expect(Self.close(a[x, 0], b[x, 0], within: 1), "\(x)") }
    }

    @Test func sizeReadsHeaderOnly() throws {
        var file = B(width: 300, height: 200)
        file.layers = [.init(width: 1, height: 1, pixels: [1, 2, 3, 4])]
        let header = Data(file.build().bytes.prefix(14 + 12))
        #expect(try XCFDecoder.size(header) == (300, 200))
        #expect(throws: OwnDecodeError.self) { try XCFDecoder.decode(header) }
    }

    @Test func userUnitLengthQuirk() throws {
        let payload = B.float(2.54) + B.be32(2) + ["centimeters", "cm", "cm", "centimeter", "centimeters"].flatMap(B.string)
        var file = B(width: 1, height: 1)
        file.extraProperties = B.be32(24) + B.be32(16) + payload  // the length GIMP wrote, shorter than the payload
        file.layers = [.init(width: 1, height: 1, pixels: [9, 8, 7, 255])]
        #expect(try XCFDecoder.decode(file.data)[0, 0] == (9, 8, 7, 255))
    }

    // MARK: Hostile input

    static var twoLayers: XCFBuilder {
        var file = B(width: 3, height: 2, version: 11, compression: 1)
        file.layers = [.init(width: 2, height: 2, pixels: Self.solid(2, 2, [255, 0, 0, 128]), x: 1),
                       .init(width: 3, height: 2, type: 0, pixels: Self.solid(3, 2, [0, 0, 255]))]
        return file
    }

    @Test func truncatedAtEveryLengthThrows() throws {
        let bytes = Self.twoLayers.build().bytes
        _ = try XCFDecoder.decode(Data(bytes))
        for n in 0..<bytes.count {
            #expect(throws: OwnDecodeError.self, "\(n)") { try XCFDecoder.decode(Data(bytes[0..<n])) }
        }
    }

    static func patched(_ built: XCFBuilder.Built, slot: Int, to value: Int) -> Data {
        var bytes = built.bytes
        let v = built.pointerSize == 8 ? B.be64(value) : B.be32(value)
        bytes.replaceSubrange(slot..<slot + built.pointerSize, with: v)
        return Data(bytes)
    }

    @Test func pointerPastTheEndThrows() throws {
        let built = Self.twoLayers.build()
        let data = Self.patched(built, slot: built.layerPointerSlots[0], to: built.bytes.count + 100)
        #expect(throws: OwnDecodeError.self) { try XCFDecoder.decode(data) }
        let tile = Self.patched(built, slot: built.tilePointerSlots[0], to: built.bytes.count)
        #expect(throws: OwnDecodeError.self) { try XCFDecoder.decode(tile) }
    }

    @Test func pointerLoopThrows() throws {
        let built = Self.twoLayers.build()
        // Offset 9 is inside the header (0 would end the layer list instead).
        for slot in [built.layerPointerSlots[0], built.tilePointerSlots[0], built.tilePointerSlots.last!] {
            #expect(throws: OwnDecodeError.self) { try XCFDecoder.decode(Self.patched(built, slot: slot, to: 9)) }
        }
    }

    @Test func hugeLayerThrows() throws {
        let built = Self.twoLayers.build()
        var bytes = built.bytes
        let at = built.layerOffsets[0]
        bytes.replaceSubrange(at..<at + 8, with: B.be32(60000) + B.be32(60000))
        #expect(bytes.count < 1024)
        #expect(throws: OwnDecodeError.self) { try XCFDecoder.decode(Data(bytes)) }
    }

    /// A v0 RGB file by hand: `layers` lists each layer record by index, every record is
    /// `layer` × `layer` and shares one hierarchy whose tile list starts with 0 (all tiles empty).
    static func tiny(canvas: Int, layer: Int, records: Int, layers: [Int]) -> Data {
        let listEnd = 34 + 4 * layers.count + 8, recordSize = 32
        let hierarchy = listEnd + records * recordSize
        var bytes = Array("gimp xcf file\0".utf8) + B.be32(canvas) + B.be32(canvas) + B.be32(0) + B.be32(0) + B.be32(0)
        for i in layers { bytes += B.be32(listEnd + i * recordSize) }
        bytes += B.be32(0) + B.be32(0)
        for _ in 0..<records {
            bytes += B.be32(layer) + B.be32(layer) + B.be32(0) + B.be32(0) + B.be32(0) + B.be32(0) + B.be32(hierarchy) + B.be32(0)
        }
        bytes += B.be32(layer) + B.be32(layer) + B.be32(3) + B.be32(hierarchy + 20) + B.be32(0)
        bytes += B.be32(layer) + B.be32(layer) + B.be32(0)
        return Data(bytes)
    }

    /// Not #expect(throws:): an image returned by mistake would be printed, all of its bytes.
    static func refused(_ data: Data) -> Bool {
        do { _ = try XCFDecoder.decode(data); return false } catch OwnDecodeError.corrupt { return true } catch { return false }
    }

    @Test func largeCanvasWithOnlyASmallLayerOpens() throws {
        var file = B(width: 3000, height: 3000, compression: 1)
        file.layers = [.init(width: 300, height: 80, pixels: Self.solid(300, 80, [1, 2, 3, 255]), x: 10, y: 20)]
        #expect(file.data.count < 8192)
        let image = try XCFDecoder.decode(file.data)
        #expect(image[10, 20] == (1, 2, 3, 255) && image[2999, 2999].a == 0)
    }

    /// GIMP stops at a 0 in a tile list and leaves the rest empty: those tiles cost no bytes, so they aren't drawn.
    @Test func missingTilesAreNotDrawn() throws {
        #expect(try XCFDecoder.decode(Self.tiny(canvas: 8, layer: 8, records: 1, layers: [0])).pixels.allSatisfy { $0 == 0 })
        var file = B(width: 70, height: 66)
        file.layers = [.init(width: 70, height: 66, type: 0, pixels: Self.solid(70, 66, [9, 8, 7]))]
        let built = file.build()
        let image = try XCFDecoder.decode(Self.patched(built, slot: built.tilePointerSlots[1], to: 0))
        #expect(image[63, 63] == (9, 8, 7, 255) && image[64, 0].a == 0 && image[0, 64].a == 0 && image[69, 65].a == 0)
    }

    @Test func layersSharingAHierarchyThrow() throws {
        #expect(Self.refused(Self.tiny(canvas: 8, layer: 8, records: 2, layers: [0, 1])))
    }

    @Test func repeatedLayerPointerThrows() throws {
        let built = Self.twoLayers.build()
        let data = Self.patched(built, slot: built.layerPointerSlots[1], to: built.layerOffsets[0])
        #expect(throws: OwnDecodeError.corrupt) { try XCFDecoder.decode(data) }
    }

    @Test func manyLayersSharingOneHierarchyThrow() throws {
        #expect(Self.refused(Self.tiny(canvas: 1024, layer: 1024, records: 100, layers: Array(0..<100))))
    }

    @Test func unknownCompressionThrows() throws {
        var file = B(width: 1, height: 1, compression: 3)
        file.layers = [.init(width: 1, height: 1, pixels: [1, 2, 3, 4])]
        #expect(throws: OwnDecodeError.unsupported) { try XCFDecoder.decode(file.data) }
    }

    @Test func notXCFIsNotThisFormat() {
        let data = Data("not an xcf file at all, just text".utf8)
        #expect(throws: OwnDecodeError.notThisFormat) { try XCFDecoder.decode(data) }
        #expect(throws: OwnDecodeError.notThisFormat) { try XCFDecoder.size(data) }
    }

    @Test func registeredForTheExtension() {
        #expect(OwnDecoders.builtIn.contains { $0.name == "GIMP XCF" && $0.extensions == ["xcf"] })
    }

    // MARK: Sample corpus

    /// True if INDEX.md lists the file with only normal layer modes (0 legacy, 28 normal).
    static func onlyNormalModes(_ name: String, index: String) -> Bool {
        guard let line = index.split(separator: "\n").first(where: { $0.hasPrefix("| \(name) |") }),
              let range = line.range(of: #"modes=\[[0-9, ]+\]"#, options: .regularExpression) else { return false }
        let modes = line[range].dropFirst(7).dropLast().split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return modes.allSatisfy { $0 == 0 || $0 == 28 }
    }

    @Test(.enabled(if: SampleCorpus.isAvailable)) func xcfCorpusMatchesReferences() throws {
        let root = try #require(SampleCorpus.root)
        let index = (try? String(contentsOf: root.appendingPathComponent("INDEX.md"), encoding: .utf8)) ?? ""
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("xcf"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        for file in files {
            let name = file.lastPathComponent
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let image: RGBAImage
            do { image = try XCFDecoder.decode(data) } catch { Issue.record("\(name): \(error)"); continue }
            // This file's linear float pixels come with a linear gray ICC profile, and its reference
            // rendering shows those linear values as if they were gamma-encoded (much darker). Linear light
            // must look like its gamma version, so it is checked against its 16-bit gamma sibling instead.
            let referenceFile = name == "kimg_birthday32fp_gray.xcf"
                ? file.deletingLastPathComponent().appendingPathComponent("kimg_birthday16_gray.xcf") : file
            guard let source = CGImageSourceCreateWithURL(SampleCorpus.reference(for: referenceFile) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil), let reference = RGBAImage(cg)
            else { Issue.record("\(name): no reference"); continue }
            let difference = SampleCorpus.difference(image, reference)
            let normal = Self.onlyNormalModes(name, index: index)
            print("XCF corpus \(name): difference \(String(format: "%.2f", difference))\(normal ? "" : " (other modes, size only)")")
            #expect(image.width == reference.width && image.height == reference.height, "\(name)")
            if normal { #expect(difference < 3, "\(name): \(difference)") }
        }
    }
}
