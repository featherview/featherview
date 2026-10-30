import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDLayersTests {
    typealias Layer = PSDFixture.FixtureLayer

    /// Pseudo-random RGBA bytes, alpha included.
    static func noise(_ count: Int, seed: UInt32 = 7) -> [UInt8] {
        var state = seed
        return (0..<count).map { _ in state = state &* 1_664_525 &+ 1_013_904_223; return UInt8(truncatingIfNeeded: state >> 24) }
    }

    static func open(_ data: Data) throws -> PSDLayers {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.psd")
        try data.write(to: url)
        return try #require(try PSDLayers(url: url))
    }

    static func layers(_ nodes: [PSDNode]) -> [PSDLayer] {
        nodes.compactMap { if case .layer(let layer) = $0 { layer } else { nil } }
    }

    /// "A,G(B,C),D" for a tree.
    static func outline(_ nodes: [PSDNode]) -> String {
        nodes.map {
            switch $0 {
            case .layer(let layer): layer.name
            case .group(let group): "\(group.name)(\(outline(group.children)))"
            }
        }.joined(separator: ",")
    }

    @Test(arguments: [(1, 0), (1, 1), (2, 1), (1, 2), (2, 3)])  // (version, channel compression)
    func readsLayerPixels(version: Int, compression: Int) throws {
        let a = Self.noise(5 * 4 * 4), b = Self.noise(3 * 3 * 4, seed: 99)
        let file = try Self.open(PSDFixture.makeLayered(width: 8, height: 6, layers: [
            Layer(name: "A", rect: (1, 2, 5, 7), pixels: a, compression: compression),
            Layer(name: "B", rect: (0, 0, 3, 3), pixels: b, compression: compression),
        ], version: version))
        #expect(file.width == 8 && file.height == 6)
        let layers = Self.layers(file.nodes)
        #expect(layers.map(\.name) == ["A", "B"])
        #expect(layers[0].rect == (1, 2, 5, 7))
        #expect(try layers[0].channels(scale: 1) == RGBAImage(width: 5, height: 4, pixels: a))
        #expect(try layers[1].channels(scale: 1) == RGBAImage(width: 3, height: 3, pixels: b))
    }

    @Test func readsGroupsBottomToTop() throws {
        let pixel: [UInt8] = [1, 2, 3, 255]
        func layer(_ name: String) -> Layer { Layer(name: name, rect: (0, 0, 1, 1), pixels: pixel) }
        let file = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [
            layer("A"),
            Layer(name: "</Layer group>", group: .divider),
            layer("B"), layer("C"),
            Layer(name: "G", blend: "pass", group: .open),
            layer("D"),
        ]))
        #expect(Self.outline(file.nodes) == "A,G(B,C),D")
        guard case .group(let group) = file.nodes[1] else { Issue.record("no group"); return }
        #expect(group.blend == "pass" && group.visible && group.opacity == 255)
    }

    @Test func readsRecordFields() throws {
        let ranges: [UInt8] = [10, 20, 200, 250, 0, 0, 255, 255,  1, 2, 3, 4, 5, 6, 7, 8,
                               0, 0, 255, 255, 0, 0, 255, 255,  0, 0, 255, 255, 30, 40, 50, 60]
        let file = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [
            Layer(name: "Base", rect: (0, 0, 1, 1), pixels: [0, 0, 0, 255]),
            Layer(name: "Top", rect: (0, 0, 1, 1), pixels: [9, 9, 9, 255], blend: "mul ", opacity: 128, clipped: true,
                  hidden: true, blocks: ["iOpa": Data([64, 0, 0, 0])], blendIf: ranges),
        ]))
        let layers = Self.layers(file.nodes)
        #expect(layers[0].blend == "norm" && layers[0].opacity == 255 && layers[0].fill == 255)
        #expect(!layers[0].clipped && layers[0].visible && layers[0].blendIf == nil)
        let top = layers[1]
        #expect(top.blend == "mul " && top.opacity == 128 && top.fill == 64 && top.clipped && !top.visible)
        #expect(top.blocks["iOpa"] == Data([64, 0, 0, 0]))
        let blendIf = try #require(top.blendIf)
        #expect(blendIf.gray.source == [10, 20, 200, 250] && blendIf.gray.backdrop == [0, 0, 255, 255])
        #expect(blendIf.red.source == [1, 2, 3, 4] && blendIf.red.backdrop == [5, 6, 7, 8])
        #expect(blendIf.blue.source == [0, 0, 255, 255] && blendIf.blue.backdrop == [30, 40, 50, 60])
    }

    @Test func layerBoundsOutsideCanvas() throws {
        let pixels = Self.noise(5 * 5 * 4)
        let file = try Self.open(PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "Off", rect: (-3, -2, 2, 3), pixels: pixels),
        ]))
        let layer = try #require(Self.layers(file.nodes).first)
        #expect(layer.rect == (-3, -2, 2, 3))
        #expect(try layer.channels(scale: 1) == RGBAImage(width: 5, height: 5, pixels: pixels))
    }

    @Test func blendingRangesPastTheRecordThrowsBeforeReadingThem() throws {
        var data = PSDFixture.makeLayered(width: 2, height: 2, layers: [
            Layer(name: "A", rect: (0, 0, 1, 1), pixels: [1, 2, 3, 255]),
        ], realComposite: nil)
        // Version 1 without resources: the record starts at byte 44, its blending ranges' length at 106.
        // A length that fits in the file but runs past the record must throw before the bytes are read.
        Self.patch(&data, 106, data.count - 110, 4)
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.psd")
        try data.write(to: url)
        let fd = Darwin.open(url.path, O_RDONLY)
        defer { close(fd) }
        var r = FileCursor(fd: fd, end: data.count)
        r.offset = 44
        #expect(throws: OwnDecodeError.corrupt) { try Record(&r, version: 1, end: data.count) }
        #expect(r.offset == 110)
    }

    @Test func maskDefaultAndDisabled() throws {
        let maskPixels = Self.noise(2 * 3)
        let file = try Self.open(PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "M", rect: (0, 0, 4, 4), pixels: Self.noise(64),
                  mask: .init(rect: (1, 1, 3, 4), pixels: maskPixels, defaultColour: 255, disabled: true), compression: 1),
        ]))
        let mask = try #require(Self.layers(file.nodes).first?.mask)
        #expect(mask.rect == (1, 1, 3, 4) && mask.defaultColour == 255 && mask.disabled && !mask.relative)
        let (rect, pixels) = try mask.pixels(scale: 1)
        #expect(rect == (1, 1, 3, 4) && pixels == maskPixels)
    }

    @Test func realCompositeFlag() throws {
        let layer = Layer(name: "A", rect: (0, 0, 1, 1), pixels: [1, 2, 3, 255])
        #expect(try !Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [layer], realComposite: false)).hasRealComposite)
        #expect(try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [layer], realComposite: true)).hasRealComposite)
        #expect(try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [layer], realComposite: nil)).hasRealComposite)
    }

    @Test func notEightBitRGBIsNil() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("grey.psd")
        try PSDFixture.make(width: 2, height: 2, pixels: Array(repeating: (0, 0, 0), count: 4), channels: 1, mode: 1).write(to: url)
        #expect(try PSDLayers(url: url) == nil)
    }

    @Test func scaledChannelsAverage() throws {
        let rgb: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (10, 20, 30), (100, 100, 100), (200, 0, 50),
                                            (2, 2, 2), (12, 22, 32), (100, 100, 100), (0, 0, 52)]
        let rows = rgb + rgb  // 4 × 4: the 4 × 2 block twice
        let pixels: [UInt8] = rows.flatMap { [$0.0, $0.1, $0.2, 255] as [UInt8] }
        let file = try Self.open(PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "A", rect: (0, 0, 4, 4), pixels: pixels),
        ]))
        let layer = try #require(Self.layers(file.nodes).first)
        let half = try #require(try layer.channels(scale: 0.5))
        #expect(layer.scaledRect(scale: 0.5) == (0, 0, 2, 2))
        let expected: [UInt8] = [6, 11, 16, 255, 100, 50, 76, 255]
        #expect(half == RGBAImage(width: 2, height: 2, pixels: expected + expected))
    }

    @Test func emptyLayerHasNoChannels() throws {
        let file = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [Layer(name: "Empty")]))
        #expect(try Self.layers(file.nodes).first?.channels(scale: 1) == nil)
    }

    @Test func corruptChannelThrows() throws {
        let layer = Layer(name: "A", rect: (0, 0, 2, 2), pixels: Self.noise(16))
        // Channel length past the end: the first channel's length sits at byte 64 of a file without resources.
        var long = PSDFixture.makeLayered(width: 2, height: 2, layers: [layer], realComposite: nil)
        long.replaceSubrange(64..<68, with: [0x7F, 0xFF, 0xFF, 0xFF])
        #expect(throws: OwnDecodeError.corrupt) { try Self.open(long) }

        // An RLE row that unpacks to 4 bytes in a 2-pixel row.
        var overrun = layer
        overrun.override[-1] = [0, 1, 0, 2, 0, 2, 0xFD, 7, 0xFD, 7]
        let rle = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [overrun]))
        #expect(throws: OwnDecodeError.corrupt) { try Self.layers(rle.nodes)[0].channels(scale: 1) }

        // A zip channel that inflates to 3 of 4 bytes.
        var short = layer
        short.override[0] = [0, 2] + PSDFixture.zlib([1, 2, 3])
        let zip = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [short]))
        #expect(throws: OwnDecodeError.corrupt) { try Self.layers(zip.nodes)[0].channels(scale: 1) }
    }
    /// Overwrites `bytes` at `offset` with `value` big-endian.
    static func patch(_ data: inout Data, _ offset: Int, _ value: Int, _ count: Int) {
        data.replaceSubrange(offset ..< offset + count, with: (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    // In a version 1 file without resources, channel `k`'s ID sits at byte 62 + 6k, the mask rect 20 bytes after the last.

    @Test func partlyCoveredCellsArePartlyTransparent() throws {
        let file = try Self.open(PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "A", rect: (1, 1, 3, 3), pixels: [UInt8](repeating: 255, count: 16),
                  mask: .init(rect: (1, 1, 3, 3), pixels: [0, 0, 0, 0], defaultColour: 255)),
        ]))
        let layer = try #require(Self.layers(file.nodes).first)
        #expect(layer.scaledRect(scale: 0.5) == (0, 0, 2, 2))
        // Each scaled cell holds one of the layer's pixels and three uncovered ones.
        #expect(try layer.channels(scale: 0.5) == RGBAImage(width: 2, height: 2, pixels: Array([[UInt8]](repeating: [255, 255, 255, 64], count: 4).joined())))
        let (rect, pixels) = try #require(layer.mask).pixels(scale: 0.5)
        #expect(rect == (0, 0, 2, 2) && pixels == [191, 191, 191, 191])
    }

    @Test func hugeRectWithoutChannelsIsEmpty() throws {
        var data = PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "A", rect: (0, 0, 1 << 24, 1 << 24),
                  mask: .init(rect: (0, 0, 1 << 24, 1 << 24), pixels: [], defaultColour: 255)),
        ], realComposite: nil)
        for k in 0..<5 { Self.patch(&data, 62 + 6 * k, 10 + k, 2) }
        let layer = try #require(Self.layers(try Self.open(data).nodes).first)
        #expect(try layer.channels(scale: 1) == nil)
        #expect(try layer.channels(scale: 0.5) == nil)
        #expect(try layer.mask?.pixels(scale: 0.5).pixels == [])
    }

    @Test func hugeRectWithShortChannelsThrows() throws {
        // 2^24 × 65536 RLE: the row counts are there, the rows aren't.
        var huge = Layer(name: "A", rect: (0, 0, 1 << 16, 1 << 24))
        for id in -1...2 { huge.override[id] = [0, 1] + [UInt8](repeating: 0, count: 1 << 17) }
        let file = try Self.open(PSDFixture.makeLayered(width: 4, height: 4, layers: [huge]))
        #expect(throws: OwnDecodeError.corrupt) { try Self.layers(file.nodes)[0].channels(scale: 1) }
        #expect(throws: OwnDecodeError.corrupt) { try Self.layers(file.nodes)[0].channels(scale: 0.5) }
    }

    @Test func rawLayerWithoutAlphaAndHugeRectThrowsBeforeAllocating() throws {
        // 100 × 100 raw colour planes (10,002 bytes each), alpha renamed to 10, rect grown to 1000 × 1000:
        // within deflate's ratio, but raw needs a byte per pixel.
        var data = PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "A", rect: (0, 0, 100, 100), pixels: Self.noise(100 * 100 * 4)),
        ], realComposite: nil)
        Self.patch(&data, 62, 10, 2)
        Self.patch(&data, 52, 1000, 4)
        Self.patch(&data, 56, 1000, 4)
        let layer = try #require(Self.layers(try Self.open(data).nodes).first)
        #expect(layer.rect == (0, 0, 1000, 1000))
        #expect(throws: OwnDecodeError.corrupt) { try layer.source.holds([-1, 0, 1, 2], 1000, 1000) }
        #expect(throws: OwnDecodeError.corrupt) { try layer.channels(scale: 0.5) }
    }

    @Test func embeddedFilesAndFilterDataAreNotKept() throws {
        let big = Data(repeating: 7, count: 64)
        let file = try Self.open(PSDFixture.makeLayered(width: 2, height: 2, layers: [
            Layer(name: "A", rect: (0, 0, 1, 1), pixels: [1, 2, 3, 255],
                  blocks: ["lnk2": big, "FEid": big, "luni": Data([0, 0, 0, 0])]),
        ]))
        let layer = try #require(Self.layers(file.nodes).first)
        #expect(layer.blocks["lnk2"] == nil && layer.blocks["FEid"] == nil)
        #expect(layer.blocks["luni"] == Data([0, 0, 0, 0]))
        #expect(try layer.channels(scale: 1) == RGBAImage(width: 1, height: 1, pixels: [1, 2, 3, 255]))
    }

    @Test func maskRectOutOfRangeThrows() throws {
        var data = PSDFixture.makeLayered(width: 4, height: 4, layers: [
            Layer(name: "A", rect: (0, 0, 1, 1), pixels: [1, 2, 3, 255], mask: .init(rect: (0, 0, 1, 1), pixels: [7])),
        ], realComposite: nil)
        for (k, v) in [Int(Int32.min), Int(Int32.min), Int(Int32.max), Int(Int32.max)].enumerated() { Self.patch(&data, 62 + 30 + 20 + 4 * k, v, 4) }
        #expect(throws: OwnDecodeError.corrupt) { try Self.open(data) }
    }

    @Test func negativePSBChannelLengthThrows() throws {
        // Version 2 without resources: the first channel's 8-byte length sits at byte 72.
        var data = PSDFixture.makeLayered(width: 2, height: 2, layers: [
            Layer(name: "A", rect: (0, 0, 2, 2), pixels: Self.noise(16)),
        ], realComposite: nil, version: 2)
        Self.patch(&data, 72, -16, 8)
        #expect(throws: OwnDecodeError.corrupt) { try Self.open(data) }
    }
}
