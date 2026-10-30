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
}
