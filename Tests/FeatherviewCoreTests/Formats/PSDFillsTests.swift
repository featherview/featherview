import CoreGraphics
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
    static func gradient(_ type: String, angle: Double, colours: [(V, Int)], opacities: [(Double, Int)] = [(100, 0), (100, 4096)],
                         extra: [(String, V)] = []) -> Data {
        block(extra + [
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
        vectorMask(subpaths: [(0, points)], flags: flags, initialFill: initialFill)
    }

    /// A vmsk block with several closed subpaths, each with its path operation (−1 joins the previous shape).
    static func vectorMask(subpaths: [(operation: Int, points: [(Double, Double)])], flags: Int = 0, initialFill: Int = 0) -> Data {
        func record(_ selector: Int, _ body: [UInt8]) -> [UInt8] { be(selector, 2) + body + [UInt8](repeating: 0, count: 24 - body.count) }
        func fixed(_ f: Double) -> [UInt8] { be(Int((f * 16_777_216).rounded()), 4) }
        var bytes = be(3, 4) + be(flags, 4) + record(6, []) + record(8, be(initialFill, 2))
        for subpath in subpaths {
            bytes += record(0, be(subpath.points.count, 2) + be(subpath.operation, 2))
            for (x, y) in subpath.points { bytes += record(1, (0..<3).flatMap { _ in fixed(y) + fixed(x) }) }
        }
        return Data(bytes)
    }

    static func square(_ from: Double, _ to: Double) -> [(Double, Double)] { [(from, from), (to, from), (to, to), (from, to)] }

    static func fillLayer(_ blocks: [String: Data], width: Int, height: Int) throws -> PSDLayer {
        try fillFile(blocks, width: width, height: height).layer
    }

    /// A one-layer file with `globalBlocks` (whole tagged blocks) after its layer info.
    static func fillFile(_ blocks: [String: Data], width: Int, height: Int, globalBlocks: [UInt8] = [],
                         more: [[String: Data]] = []) throws -> (file: PSDLayers, layer: PSDLayer) {
        let layers = ([blocks] + more).map { Layer(name: "Fill", blocks: $0) }
        var data = PSDFixture.makeLayered(width: width, height: height, layers: layers)
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

    /// Photoshop writes the initial fill record as 1 on masks with shapes too, and draws only the shapes; it decides
    /// only for a mask without shapes, which then reveals everything (1) or nothing (0), or the reverse when inverted.
    @Test func initialFillRecordOnlyDecidesAnEmptyMask() throws {
        let colour = Self.block([("Clr ", Self.rgb(9, 9, 9))])
        let shaped = try Self.fillLayer(["SoCo": colour, "vmsk": Self.vectorMask(Self.square(0.25, 0.75), initialFill: 1)], width: 8, height: 8)
        let mask = try #require(try PSDFills.vectorMask(shaped, canvas: (8, 8), scale: 1))
        #expect(mask.rect == (2, 2, 6, 6))
        #expect(mask.pixels.allSatisfy { $0 == 255 })

        for (initialFill, flags, expected) in [(1, 0, UInt8(255)), (1, 1, 0), (0, 0, 0), (0, 1, 255)] {
            let empty = try Self.fillLayer(["SoCo": colour, "vmsk": Self.vectorMask(subpaths: [], flags: flags, initialFill: initialFill)],
                                           width: 8, height: 8)
            let mask = try #require(try PSDFills.vectorMask(empty, canvas: (8, 8), scale: 1))
            let image = try #require(try PSDFills.content(empty, canvas: (8, 8), patterns: [:], scale: 1))
            let alphas = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
            #expect(mask.pixels.allSatisfy { $0 == expected } && alphas.allSatisfy { $0 == expected },
                    "initial fill \(initialFill), flags \(flags)")
        }
    }

    @Test func invertedAndDisabledVectorMasks() throws {
        let path = Self.square(0.25, 0.75)
        for inverted in [Self.vectorMask(path, flags: 1), Self.vectorMask(path, flags: 1, initialFill: 1)] {
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

    /// A noise gradient whose ranges are one colour draws that colour, in RGB, HSB or Lab (each in percent; Lab into the
    /// file's colour space, here Adobe RGB).
    @Test func noiseGradientsInEveryColourSpace() throws {
        for (space, values, expected) in [("RGBC", [80.0, 40, 20], [204, 102, 51]), ("HSBl", [8.3343, 60, 80], [204, 143, 82]),
                                          ("LbCl", [60.0, 60, 60], [178, 126, 102])] {
            let range = V.list((values + [100]).map { .doub($0) })
            let block = Self.block([("Angl", .unit("#Ang", 90)), ("Type", .enm("GrdT", "Lnr ")), ("Grad", .obj("Grdn", [
                ("GrdF", .enm("GrdF", "ClNs")), ("ClrS", .enm("ClrS", space)), ("Mnm ", range), ("Mxm ", range)]))])
            let image = try #require(try PSDFills.content(try Self.fillLayer(["GdFl": block], width: 2, height: 2),
                                                          canvas: (2, 2), patterns: [:], scale: 1,
                                                          rgb: CGColorSpace(name: CGColorSpace.adobeRGB1998)))
            let p = Self.pixel(image, 1, 1)
            #expect(zip(p.prefix(3), expected).allSatisfy { abs(Int($0) - $1) <= 2 }, "\(space): \(p)")
        }
    }

    /// The linear interpolation method mixes colours in linear light: half way from black to white is sRGB's 188, not 128.
    @Test func linearMethodMixesInLinearLight() throws {
        let method: [(String, V)] = [("gradientsInterpolationMethod", .enm("gradientInterpolationMethodType", "Lnr "))]
        let layer = try Self.fillLayer(["GdFl": Self.gradient("Lnr ", angle: 0, colours: [(Self.rgb(0, 0, 0), 0), (Self.rgb(255, 255, 255), 4096)],
                                                              extra: method)], width: 64, height: 1)
        let image = try #require(try PSDFills.content(layer, canvas: (64, 1), patterns: [:], scale: 1))
        #expect(abs(Int(Self.pixel(image, 32, 0)[0]) - 188) <= 3)
        #expect(Self.pixel(image, 0, 0)[0] <= 30 && Self.pixel(image, 63, 0)[0] >= 251)
    }

    /// Smoothness (Intr, of 4096) eases each stretch between stops into a smoothstep, so a quarter of the way along is
    /// darker than a quarter of the colour; without a box flag the gradient spans the shape, not the canvas.
    @Test func smoothnessEasesAndShapesAlign() throws {
        let stops: [(V, Int)] = [(Self.rgb(0, 0, 0), 0), (Self.rgb(255, 255, 255), 4096)]
        let smooth = try Self.fillLayer(["GdFl": Self.gradient("Lnr ", angle: 0, colours: stops)], width: 64, height: 1)
        let image = try #require(try PSDFills.content(smooth, canvas: (64, 1), patterns: [:], scale: 1))
        #expect(abs(Int(Self.pixel(image, 16, 0)[0]) - 41) <= 3)  // smoothstep(0.26) · 255
        let shaped = try Self.fillLayer(["GdFl": Self.gradient("Lnr ", angle: 0, colours: stops),
                                         "vmsk": Self.vectorMask(Self.square(0.5, 1))], width: 64, height: 64)
        let half = try #require(try PSDFills.content(shaped, canvas: (64, 64), patterns: [:], scale: 1))
        #expect(Self.pixel(half, 0, 16)[0] <= 2 && Self.pixel(half, 31, 16)[0] >= 253)
    }

    /// "Snap to pixel" (sn2P) puts a vector mask's points on whole canvas pixels: an edge at 2.4 px covers pixel 2 fully.
    @Test func snappedVectorMasksHaveWholePixelEdges() throws {
        let path = Self.vectorMask(Self.square(2.4 / 8, 5.6 / 8))
        let loose = try #require(try PSDFills.vectorMask(try Self.fillLayer(["vmsk": path], width: 8, height: 8), canvas: (8, 8), scale: 1))
        let snapped = try #require(try PSDFills.vectorMask(try Self.fillLayer(["vmsk": path, "sn2P": Data([0, 0, 0, 1])], width: 8, height: 8),
                                                           canvas: (8, 8), scale: 1))
        #expect(loose.rect == (2, 2, 6, 6) && loose.pixels[0] < 200)
        #expect(snapped.rect == (2, 2, 6, 6) && snapped.pixels.allSatisfy { $0 == 255 })
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
        // Built in typed steps: as long chains the CI compiler gives up type-checking them.
        var vma: [UInt8] = [0, 0, 2, 2, 24].flatMap { Self.be($0, 4) }
        for c in 0..<26 {
            guard c < 3 else { vma += Self.be(0, 4); continue }
            let plane: [UInt8] = colours.map { $0[c] }
            var data: [UInt8]
            if c == 1 {
                let rows: [[UInt8]] = [0, 1].map { PSDFixture.packBits(Array(plane[$0 * 2 ..< $0 * 2 + 2])) }
                data = [1]
                for row in rows { data += Self.be(row.count, 2) }
                for row in rows { data += row }
            } else {
                data = [0] + plane
            }
            var channel: [UInt8] = [8, 0, 0, 2, 2].flatMap { Self.be($0, 4) }
            channel += Self.be(8, 2)
            channel += data
            vma += Self.be(1, 4)
            vma += Self.be(channel.count, 4)
            vma += channel
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

        // A phase far off the canvas still tiles, without overflowing an Int.
        let far = Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("Four")), ("Idnt", .text(id))])),
                              ("phase", .obj("Pnt ", [("Hrzn", .doub(1e300)), ("Vrtc", .doub(-1e300))]))])
        let farLayer = try Self.fillLayer(["PtFl": far], width: 5, height: 3)
        #expect(try PSDFills.content(farLayer, canvas: (5, 3), patterns: patterns, scale: 1)?.width == 5)
    }

    @Test func nonFiniteNumbersAreDamage() throws {
        func throwsCorrupt(_ blocks: [String: Data]) throws {
            let layer = try Self.fillLayer(blocks, width: 4, height: 4)
            #expect(throws: OwnDecodeError.corrupt) { try PSDFills.content(layer, canvas: (4, 4), patterns: [:], scale: 1) }
        }
        let black = Self.rgb(0, 0, 0), white = Self.rgb(255, 255, 255)
        try throwsCorrupt(["SoCo": Self.block([("Clr ", Self.rgb(.nan, 0, 0))])])
        try throwsCorrupt(["SoCo": Self.block([("Clr ", .obj("HSBC", [("H   ", .unit("#Ang", .infinity)), ("Strt", .doub(50)), ("Brgh", .doub(50))]))])])
        try throwsCorrupt(["GdFl": Self.gradient("Lnr ", angle: .nan, colours: [(black, 0), (white, 4096)])])
        try throwsCorrupt(["GdFl": Self.gradient("Lnr ", angle: 0, colours: [(black, 0), (white, 4096)], opacities: [(.nan, 0), (100, 4096)])])
        let nanStops = Self.block([("Angl", .unit("#Ang", 0)), ("Type", .enm("GrdT", "Lnr ")), ("Grad", .obj("Grdn", [
            ("GrdF", .enm("GrdF", "CstS")),
            ("Clrs", .list([0, 1].map { _ in .obj("Clrt", [("Clr ", black), ("Lctn", .doub(.nan))]) })),
        ]))])
        try throwsCorrupt(["GdFl": nanStops])
    }

    @Test func hugeFiniteNumbersStayInRange() throws {
        // Brightness 1e308 with full saturation once made ∞ × 0 = NaN; an offset of 1e300 made ∞ − ∞.
        let hsb = try Self.fillLayer(["SoCo": Self.block([("Clr ", .obj("HSBC", [("H   ", .doub(0)), ("Strt", .doub(100)), ("Brgh", .doub(1e308))]))])],
                                     width: 2, height: 2)
        #expect(try PSDFills.content(hsb, canvas: (2, 2), patterns: [:], scale: 1)?.width == 2)
        let far = Self.block([("Angl", .unit("#Ang", 45)), ("Type", .enm("GrdT", "Lnr ")),
                          ("Ofst", .obj("Pnt ", [("Hrzn", .doub(1e300)), ("Vrtc", .doub(1e300))])),
                          ("Scl ", .unit("#Prc", 1e300)),
                          ("Grad", .obj("Grdn", [("GrdF", .enm("GrdF", "CstS")),
                                                 ("Clrs", .list([.obj("Clrt", [("Clr ", Self.rgb(9, 9, 9)), ("Lctn", .doub(1e300))])]))]))])
        let gradient = try Self.fillLayer(["GdFl": far], width: 2, height: 2)
        #expect(try PSDFills.content(gradient, canvas: (2, 2), patterns: [:], scale: 1)?.width == 2)
    }

    /// A Patt block holding one RGB pattern of the claimed size whose channels are `channels` (red, green,
    /// blue, user mask, sheet mask), the rest unwritten.
    static func claimedPattern(width: Int, height: Int, channels: [[UInt8]], id: String = "x") -> [UInt8] {
        var vma = Self.be(0, 4) + Self.be(0, 4) + Self.be(height, 4) + Self.be(width, 4) + Self.be(3, 4)
        for c in 0..<5 {
            guard c < channels.count else { vma += Self.be(0, 4); continue }
            let channel = Self.be(8, 4) + Self.be(0, 4) + Self.be(0, 4) + Self.be(height, 4) + Self.be(width, 4) + Self.be(8, 2) + channels[c]
            vma += Self.be(1, 4) + Self.be(channel.count, 4) + channel
        }
        var pattern = Self.be(1, 4) + Self.be(3, 4) + Self.be(height, 2) + Self.be(width, 2) + Self.unicode("") + [UInt8(id.utf8.count)] + Array(id.utf8)
        pattern += Self.be(3, 4) + Self.be(vma.count, 4) + vma
        var patt = Self.be(pattern.count, 4) + pattern
        while patt.count % 4 != 0 { patt.append(0) }
        return Array("8BIMPatt".utf8) + Self.be(patt.count, 4) + patt
    }

    @Test func patternSizeIsBoundedByItsData() throws {
        // 4,096 × 4,096 claimed: no planes at all, and PackBits rows of 0 bytes both throw before allocating.
        let fill = Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("")), ("Idnt", .text("x"))]))])
        for channels in [[], [[1] + [UInt8](repeating: 0, count: 4096 * 2)]] as [[[UInt8]]] {
            let (file, _) = try Self.fillFile(["PtFl": fill], width: 2, height: 2, globalBlocks: Self.claimedPattern(width: 4096, height: 4096, channels: channels))
            #expect(throws: OwnDecodeError.corrupt) { try PSDFills.patterns(file) }
        }
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

    @Test func alignedGradientSpansTheWholeShapeOffTheCanvas() throws {
        // The shape runs from x = −50 to 50 on a 100 px canvas: the ramp's middle sits at the canvas's left edge.
        let black = Self.rgb(0, 0, 0), white = Self.rgb(255, 255, 255)
        let fill = Self.gradient("Lnr ", angle: 0, colours: [(black, 0), (white, 4096)], extra: [("Algn", .bool(true))])
        let layer = try Self.fillLayer(["GdFl": fill, "vmsk": Self.vectorMask([(-0.5, 0), (0.5, 0), (0.5, 1), (-0.5, 1)])], width: 100, height: 2)
        let image = try #require(try PSDFills.content(layer, canvas: (100, 2), patterns: [:], scale: 1))
        #expect(image.width == 50)
        #expect(abs(Int(Self.pixel(image, 0, 0)[0]) - 129) <= 3)
        #expect(abs(Int(Self.pixel(image, 25, 0)[0]) - 217) <= 3)  // three quarters along, eased by full smoothness
    }

    @Test func pathOperationsCombineShapes() throws {
        let a = Self.square(0, 0.5), b = Self.square(0.25, 0.75), hole = Self.square(0.125, 0.375)
        func coverage(_ subpaths: [(operation: Int, points: [(Double, Double)])], _ points: [(Int, Int)]) throws -> [UInt8] {
            let layer = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(1, 2, 3))]), "vmsk": Self.vectorMask(subpaths: subpaths)],
                                           width: 16, height: 16)
            let mask = try #require(try PSDFills.vectorMask(layer, canvas: (16, 16), scale: 1))
            let w = mask.rect.right - mask.rect.left
            return points.map { x, y in
                guard (mask.rect.left..<mask.rect.right).contains(x), (mask.rect.top..<mask.rect.bottom).contains(y) else { return 0 }
                return mask.pixels[(y - mask.rect.top) * w + x - mask.rect.left]
            }
        }
        // Points in a only, in both, in b only, in neither.
        let probe = [(2, 2), (6, 6), (10, 10), (14, 1)]
        #expect(try coverage([(1, a), (1, b)], probe) == [255, 255, 255, 0])
        #expect(try coverage([(3, a), (3, b)], probe) == [0, 255, 0, 0])
        #expect(try coverage([(1, a), (2, b)], probe) == [255, 0, 0, 0])
        #expect(try coverage([(2, a)], probe) == [0, 0, 255, 255])
        #expect(try coverage([(0, a), (0, b)], probe) == [255, 0, 255, 0])
        // −1 continues the previous shape: a with a hole, then united with b.
        #expect(try coverage([(1, a), (-1, hole)], [(1, 1), (4, 4)]) == [255, 0])
        #expect(try coverage([(1, a), (-1, hole), (1, b)], [(1, 1), (4, 4), (2, 4)]) == [255, 255, 0])
    }

    @Test func onlyReferencedPatternsAreDecoded() throws {
        // A damaged pattern no layer uses costs nothing and breaks nothing.
        let unused = Self.claimedPattern(width: 65535, height: 65535, channels: [])
        let (file, _) = try Self.fillFile(["SoCo": Self.block([("Clr ", Self.rgb(1, 2, 3))])], width: 2, height: 2, globalBlocks: unused)
        #expect(try PSDFills.patterns(file).isEmpty)

        // One used but past the size cap is refused, so the file falls back to ImageIO.
        let side = 4097
        let row = PSDFixture.packBits([UInt8](repeating: 0, count: side))
        let plane: [UInt8] = [1] + (0..<side).flatMap { _ in Self.be(row.count, 2) } + (0..<side).flatMap { _ in row }
        let huge = Self.claimedPattern(width: side, height: side, channels: [plane, plane, plane])
        let fill = Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("")), ("Idnt", .text("x"))]))])
        let (used, _) = try Self.fillFile(["PtFl": fill], width: 2, height: 2, globalBlocks: huge)
        #expect(throws: OwnDecodeError.unsupported) { try PSDFills.patterns(used) }
    }

    @Test func unusedChannelsAreSkipped() throws {
        // The user mask is never read, so a damaged one is skipped, not decoded (nor taken for transparency).
        let raw: [UInt8] = [0, 9, 9, 9, 9], damaged: [UInt8] = [9, 0, 0, 0, 0]
        let fill = Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("")), ("Idnt", .text("x"))]))])
        let (file, _) = try Self.fillFile(["PtFl": fill], width: 2, height: 2,
                                          globalBlocks: Self.claimedPattern(width: 2, height: 2, channels: [raw, raw, raw, damaged]))
        let tile = try #require(try PSDFills.patterns(file)["x"])
        #expect(tile.pixels == [UInt8]((0..<4).flatMap { _ in [9, 9, 9, 255] }))
    }

    @Test func usedPatternsShareOneSizeCap() throws {
        // Two patterns, each under the cap, together over it: the file falls back instead of holding both.
        let side = 2900
        #expect(side * side <= PSDFills.maxPatternPixels && 2 * side * side > PSDFills.maxPatternPixels)
        let row = PSDFixture.packBits([UInt8](repeating: 0, count: side))
        let plane: [UInt8] = [1] + (0..<side).flatMap { _ in Self.be(row.count, 2) } + (0..<side).flatMap { _ in row }
        func fill(_ id: String) -> Data { Self.block([("Ptrn", .obj("Ptrn", [("Nm  ", .text("")), ("Idnt", .text(id))]))]) }
        // Both in one Patt block: the patterns after each block's 12-byte header.
        let both = ["a", "b"].flatMap { Self.claimedPattern(width: side, height: side, channels: [plane, plane, plane], id: $0).dropFirst(12) }
        let global = Array("8BIMPatt".utf8) + Self.be(both.count, 4) + both
        let (file, _) = try Self.fillFile(["PtFl": fill("a")], width: 2, height: 2, globalBlocks: global, more: [["PtFl": fill("b")]])
        #expect(throws: OwnDecodeError.unsupported) { _ = try PSDFills.patterns(file) }
    }

    @Test func manyShapesCostTheirOwnArea() throws {
        // 400 small squares (a logo's glyphs) over a 1,000 × 1,000 mask: drawn in milliseconds, not one
        // pass over the whole mask per shape.
        let squares = (0..<400).map { i -> (operation: Int, points: [(Double, Double)]) in
            let x = Double(i % 20) / 20, y = Double(i / 20) / 20
            return (1, [(x, y), (x + 0.025, y), (x + 0.025, y + 0.025), (x, y + 0.025)])
        }
        let layer = try Self.fillLayer(["SoCo": Self.block([("Clr ", Self.rgb(1, 2, 3))]), "vmsk": Self.vectorMask(subpaths: squares)],
                                       width: 1000, height: 1000)
        let clock = ContinuousClock()
        var mask: (rect: PSDRect, pixels: [UInt8], bounds: PSDRect)?
        let elapsed = try clock.measure { mask = try PSDFills.vectorMask(layer, canvas: (1000, 1000), scale: 1) }
        let m = try #require(mask)
        let w = m.rect.right - m.rect.left
        #expect(m.rect.top == 0 && m.rect.left == 0 && (975...976).contains(w))
        #expect(m.pixels[10 * w + 10] == 255 && m.pixels[30 * w + 30] == 0)
        #expect(elapsed < .milliseconds(500))
    }
}
