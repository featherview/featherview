import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDFillsTests {
    typealias Layer = PSDFixture.FixtureLayer

    // MARK: Building blocks

    static func be(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }

    /// Descriptor values as the tests write them.
    indirect enum V {
        case doub(Double), unit(String, Double), long(Int), bool(Bool), text(String), enm(String, String), list([V])
        case obj(String, [(String, V)])
    }

    static func id(_ s: String) -> [UInt8] { (s.utf8.count == 4 ? be(0, 4) : be(s.utf8.count, 4)) + Array(s.utf8) }
    static func unicode(_ s: String) -> [UInt8] { be(s.utf16.count, 4) + s.utf16.flatMap { be(Int($0), 2) } }
    static func object(_ cls: String, _ items: [(String, V)]) -> [UInt8] {
        unicode("") + id(cls) + be(items.count, 4) + items.flatMap { id($0.0) + value($0.1) }
    }
    static func value(_ v: V) -> [UInt8] {
        switch v {
        case .doub(let d): Array("doub".utf8) + be(Int(truncatingIfNeeded: d.bitPattern), 8)
        case .unit(let u, let d): Array("UntF".utf8) + Array(u.utf8) + be(Int(truncatingIfNeeded: d.bitPattern), 8)
        case .long(let n): Array("long".utf8) + be(n, 4)
        case .bool(let b): Array("bool".utf8) + [b ? 1 : 0]
        case .text(let s): Array("TEXT".utf8) + unicode(s)
        case .enm(let t, let e): Array("enum".utf8) + id(t) + id(e)
        case .list(let l): Array("VlLs".utf8) + be(l.count, 4) + l.flatMap(value)
        case .obj(let cls, let items): Array("Objc".utf8) + object(cls, items)
        }
    }
    /// A tagged block's data: version 16, then the descriptor.
    static func block(_ items: [(String, V)]) -> Data { Data(be(16, 4) + object("null", items)) }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> V { .obj("RGBC", [("Rd  ", .doub(r)), ("Grn ", .doub(g)), ("Bl  ", .doub(b))]) }

    /// A GdFl block: colour stops (colour, location 0…4096), transparency stops (percent, location).
    static func gradient(_ type: String, angle: Double, colours: [(V, Int)], opacities: [(Double, Int)] = [(100, 0), (100, 4096)]) -> Data {
        block([
            ("Angl", .unit("#Ang", angle)), ("Type", .enm("GrdT", type)),
            ("Grad", .obj("Grdn", [
                ("Nm  ", .text("Test")), ("GrdF", .enm("GrdF", "CstS")), ("Intr", .doub(4096)),
                ("Clrs", .list(colours.map { .obj("Clrt", [("Clr ", $0.0), ("Type", .enm("Clry", "UsrS")), ("Lctn", .long($0.1)), ("Mdpn", .long(50))]) })),
                ("Trns", .list(opacities.map { .obj("TrnS", [("Opct", .unit("#Prc", $0.0)), ("Lctn", .long($0.1)), ("Mdpn", .long(50))]) })),
            ])),
        ])
    }

    /// A vmsk block: version 3, flags, a fill rule record, the initial fill record, then one closed
    /// subpath through `points` (x, y as fractions of the canvas), corners without handles.
    static func vectorMask(_ points: [(Double, Double)], flags: Int = 0, initialFill: Int = 0) -> Data {
        func record(_ selector: Int, _ body: [UInt8]) -> [UInt8] { be(selector, 2) + body + [UInt8](repeating: 0, count: 24 - body.count) }
        func fixed(_ f: Double) -> [UInt8] { be(Int((f * 16_777_216).rounded()), 4) }
        var bytes = be(3, 4) + be(flags, 4) + record(6, []) + record(8, be(initialFill, 2)) + record(0, be(points.count, 2))
        for (x, y) in points { bytes += record(1, (0..<3).flatMap { _ in fixed(y) + fixed(x) }) }
        return Data(bytes)
    }

    static func square(_ from: Double, _ to: Double) -> [(Double, Double)] { [(from, from), (to, from), (to, to), (from, to)] }

    static func fillLayer(_ blocks: [String: Data], width: Int, height: Int) throws -> PSDLayer {
        try fillFile(blocks, width: width, height: height).layer
    }

    /// A one-layer file with `globalBlocks` (whole tagged blocks) after its layer info.
    static func fillFile(_ blocks: [String: Data], width: Int, height: Int, globalBlocks: [UInt8] = []) throws -> (file: PSDLayers, layer: PSDLayer) {
        var data = PSDFixture.makeLayered(width: width, height: height, layers: [Layer(name: "Fill", blocks: blocks)])
        if !globalBlocks.isEmpty {
            // The section's length sits after the header and resources; the global blocks go at its end.
            let resources = Int(data[30]) << 24 | Int(data[31]) << 16 | Int(data[32]) << 8 | Int(data[33])
            let at = 34 + resources
            let length = data[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
            data.replaceSubrange(at..<at + 4, with: be(length + globalBlocks.count, 4))
            data.insert(contentsOf: globalBlocks, at: at + 4 + length)
        }
        let file = try PSDLayersTests.open(data)
        return (file, try #require(PSDLayersTests.layers(file.nodes).first))
    }

    static func pixel(_ image: RGBAImage, _ x: Int, _ y: Int) -> [UInt8] { Array(image.pixels[(y * image.width + x) * 4 ..< (y * image.width + x) * 4 + 4]) }

    // MARK: Tests

    @Test func solidColourFillsTheCanvas() throws {
        let layer = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(255, 128, 0))])], width: 4, height: 3)
        let image = try #require(try PSDFills.content(layer, canvas: (4, 3), patterns: [:], scale: 1))
        #expect(image.width == 4 && image.height == 3)
        for y in 0..<3 { for x in 0..<4 { #expect(Self.pixel(image, x, y) == [255, 128, 0, 255]) } }
    }

    @Test func layerWithoutFillHasNoContent() throws {
        let layer = try Self.fillLayer([:], width: 4, height: 3)
        #expect(try PSDFills.content(layer, canvas: (4, 3), patterns: [:], scale: 1) == nil)
    }

    @Test func vectorMaskCutsTheLayer() throws {
        // 2.5 … 5.5 on an 8 × 8 canvas: pixels 3 and 4 inside, 2 and 5 half covered.
        let layer = try Self.fillLayer([
            "SoCo": Self.block([("Clr ", Self.rgb(0, 0, 255))]),
            "vmsk": Self.vectorMask(Self.square(2.5 / 8, 5.5 / 8)),
        ], width: 8, height: 8)
        let mask = try #require(try PSDFills.vectorMask(layer, canvas: (8, 8), scale: 1))
        #expect(mask.rect == (2, 2, 6, 6))
        #expect(mask.pixels.count == 16)
        #expect(mask.pixels[1 * 4 + 1] == 255 && mask.pixels[2 * 4 + 2] == 255)
        #expect(abs(Int(mask.pixels[1 * 4 + 0]) - 128) <= 2)  // left edge, half covered
        #expect(abs(Int(mask.pixels[0]) - 64) <= 2)           // corner, a quarter
        let image = try #require(try PSDFills.content(layer, canvas: (8, 8), patterns: [:], scale: 1))
        #expect(image.width == 4 && image.height == 4)       // only the mask's bounds; outside is clear
        #expect(Self.pixel(image, 1, 1) == [0, 0, 255, 255])
        #expect(Self.pixel(image, 0, 1)[3] == mask.pixels[1 * 4 + 0])
    }

    @Test func invertedAndDisabledVectorMasks() throws {
        let path = Self.square(0.25, 0.75)
        for inverted in [Self.vectorMask(path, flags: 1), Self.vectorMask(path, initialFill: 1)] {
            let layer = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(9, 9, 9))]), "vmsk": inverted], width: 8, height: 8)
            let mask = try #require(try PSDFills.vectorMask(layer, canvas: (8, 8), scale: 1))
            #expect(mask.rect == (0, 0, 8, 8))
            #expect(mask.pixels[0] == 255 && mask.pixels[4 * 8 + 4] == 0)
            let image = try #require(try PSDFills.content(layer, canvas: (8, 8), patterns: [:], scale: 1))
            #expect(image.width == 8 && Self.pixel(image, 0, 0) == [9, 9, 9, 255] && Self.pixel(image, 4, 4)[3] == 0)
        }
        let disabled = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(9, 9, 9))]), "vmsk": Self.vectorMask(path, flags: 4)],
                                          width: 8, height: 8)
        #expect(try PSDFills.vectorMask(disabled, canvas: (8, 8), scale: 1) == nil)
        let image = try #require(try PSDFills.content(disabled, canvas: (8, 8), patterns: [:], scale: 1))
        #expect(image.width == 8 && image.height == 8 && image.pixels.allSatisfy { $0 == 9 || $0 == 255 })
    }

    @Test func linearGradientEndsAndMiddle() throws {
        // At 90° the gradient runs upwards, as Photoshop draws it: its first stop at the bottom.
        let layer = try Self.fillLayer(["GdFl": Self.gradient("Lnr ", angle: 90, colours: [(Self.rgb(0, 0, 0), 0), (Self.rgb(255, 255, 255), 4096)])],
                                       width: 4, height: 64)
        let image = try #require(try PSDFills.content(layer, canvas: (4, 64), patterns: [:], scale: 1))
        #expect(Self.pixel(image, 2, 63)[0] <= 4)
        #expect(Self.pixel(image, 2, 0)[0] >= 251)
        #expect(abs(Int(Self.pixel(image, 2, 32)[0]) - 128) <= 4)
        #expect(Self.pixel(image, 0, 10) == Self.pixel(image, 3, 10))
        #expect(Self.pixel(image, 1, 20)[3] == 255)
    }

    @Test func radialAndReflectedGradients() throws {
        let stops: [(V, Int)] = [(Self.rgb(0, 0, 0), 0), (Self.rgb(255, 255, 255), 4096)]
        let radial = try #require(try PSDFills.content(
            try Self.fillLayer(["GdFl": Self.gradient("Rdl ", angle: 90, colours: stops)], width: 65, height: 65),
            canvas: (65, 65), patterns: [:], scale: 1))
        #expect(Self.pixel(radial, 32, 32)[0] <= 2)
        #expect(Self.pixel(radial, 0, 32)[0] >= 245)
        #expect(Self.pixel(radial, 0, 0)[0] == 255)
        #expect(Self.pixel(radial, 16, 32) == Self.pixel(radial, 32, 16))

        let reflected = try #require(try PSDFills.content(
            try Self.fillLayer(["GdFl": Self.gradient("Rflc", angle: 90, colours: stops)], width: 65, height: 65),
            canvas: (65, 65), patterns: [:], scale: 1))
        #expect(Self.pixel(reflected, 10, 32)[0] <= 2)
        #expect(Self.pixel(reflected, 10, 0)[0] >= 245 && Self.pixel(reflected, 10, 64)[0] >= 245)
        for y in 0..<65 { #expect(Self.pixel(reflected, 5, y) == Self.pixel(reflected, 5, 64 - y)) }
    }

    @Test func transparencyStops() throws {
        // At 0° the gradient runs left to right.
        let layer = try Self.fillLayer(["GdFl": Self.gradient("Lnr ", angle: 0, colours: [(Self.rgb(255, 0, 0), 0), (Self.rgb(255, 0, 0), 4096)],
                                                              opacities: [(100, 0), (0, 4096)])], width: 64, height: 2)
        let image = try #require(try PSDFills.content(layer, canvas: (64, 2), patterns: [:], scale: 1))
        #expect(Self.pixel(image, 0, 0)[3] >= 251)
        #expect(Self.pixel(image, 63, 1)[3] <= 4)
        #expect(abs(Int(Self.pixel(image, 32, 0)[3]) - 128) <= 4)
        #expect(Array(Self.pixel(image, 40, 1).prefix(3)) == [255, 0, 0])
    }

    @Test func patternTiles() throws {
        // A 2 × 2 RGB pattern in the global Patt block, the green channel PackBits, the others raw.
        let colours: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
        var vma = Self.be(0, 4) + Self.be(0, 4) + Self.be(2, 4) + Self.be(2, 4) + Self.be(24, 4)
        for c in 0..<26 {
            guard c < 3 else { vma += Self.be(0, 4); continue }
            let plane = colours.map { $0[c] }
            let data: [UInt8] = c == 1
                ? [1] + [0, 1].flatMap { Self.be(PSDFixture.packBits(Array(plane[$0 * 2 ..< $0 * 2 + 2])).count, 2) }
                    + [0, 1].flatMap { PSDFixture.packBits(Array(plane[$0 * 2 ..< $0 * 2 + 2])) }
                : [0] + plane
            let channel = Self.be(8, 4) + Self.be(0, 4) + Self.be(0, 4) + Self.be(2, 4) + Self.be(2, 4) + Self.be(8, 2) + data
            vma += Self.be(1, 4) + Self.be(channel.count, 4) + channel
        }
        let id = "pat-1"
        var pattern = Self.be(1, 4) + Self.be(3, 4) + Self.be(2, 2) + Self.be(2, 2) + Self.unicode("Four") + [UInt8(id.utf8.count)] + Array(id.utf8)
        pattern += Self.be(3, 4) + Self.be(vma.count, 4) + vma
        var patt = Self.be(pattern.count, 4) + pattern
        while patt.count % 4 != 0 { patt.append(0) }
        let global = Array("8BIMPatt".utf8) + Self.be(patt.count, 4) + patt

        let fill = Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("Four")), ("Idnt", .text(id))]))])
        let (file, layer) = try Self.fillFile(["PtFl": fill], width: 5, height: 3, globalBlocks: global)
        let patterns = try PSDFills.patterns(file)
        let tile = try #require(patterns[id])
        #expect(tile.width == 2 && tile.height == 2)
        #expect(tile.pixels == colours.flatMap { $0 + [255] })
        let image = try #require(try PSDFills.content(layer, canvas: (5, 3), patterns: patterns, scale: 1))
        #expect(image.width == 5 && image.height == 3)
        for y in 0..<3 { for x in 0..<5 { #expect(Self.pixel(image, x, y) == colours[(y % 2) * 2 + x % 2] + [255]) } }
        #expect(throws: OwnDecodeError.corrupt) { try PSDFills.content(layer, canvas: (5, 3), patterns: [:], scale: 1) }
    }

    @Test func scaledVectorMask() throws {
        let layer = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(1, 2, 3))]), "vmsk": Self.vectorMask(Self.square(0.25, 0.75))],
                                       width: 16, height: 16)
        let full = try #require(try PSDFills.vectorMask(layer, canvas: (16, 16), scale: 1))
        #expect(full.rect == (4, 4, 12, 12) && full.pixels == [UInt8](repeating: 255, count: 64))
        let half = try #require(try PSDFills.vectorMask(layer, canvas: (16, 16), scale: 0.5))
        #expect(half.rect == (2, 2, 6, 6) && half.pixels == [UInt8](repeating: 255, count: 16))
        let image = try #require(try PSDFills.content(layer, canvas: (16, 16), patterns: [:], scale: 0.5))
        #expect(image.width == 4 && image.height == 4 && Self.pixel(image, 3, 3) == [1, 2, 3, 255])
    }
}
