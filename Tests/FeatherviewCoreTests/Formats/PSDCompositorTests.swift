import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDCompositorTests {
    typealias Layer = PSDFixture.FixtureLayer
    typealias Mask = PSDFixture.FixtureMask

    static func render(_ width: Int, _ height: Int, _ layers: [Layer], scale: Double = 1,
                       adjustment: @escaping @Sendable (PSDLayer) -> PSDCompositor.Adjust? = { _ in nil }) throws -> RGBAImage {
        let file = try PSDLayersTests.open(PSDFixture.makeLayered(width: width, height: height, layers: layers))
        return try PSDCompositor(file, adjustment: adjustment).render(scale: scale)
    }

    /// A `w × h` layer at (top, left) of one RGBA colour.
    static func solid(_ name: String, _ top: Int, _ left: Int, _ w: Int, _ h: Int, _ rgba: [UInt8]) -> Layer {
        Layer(name: name, rect: (top, left, top + h, left + w), pixels: Array([[UInt8]](repeating: rgba, count: w * h).joined()))
    }

    static func group(_ name: String, blend: String, opacity: UInt8 = 255, mask: Mask? = nil, _ children: [Layer]) -> [Layer] {
        [Layer(name: "</Layer group>", group: .divider)] + children
            + [Layer(name: name, blend: blend, opacity: opacity, mask: mask, group: .open)]
    }

    @Test func normalLayersStackLikeSourceOver() throws {
        let image = try Self.render(3, 1, [
            Layer(name: "A", rect: (0, 0, 1, 2), pixels: [200, 0, 0, 255, 0, 0, 0, 0]),
            Layer(name: "B", rect: (0, 0, 1, 2), pixels: [0, 0, 200, 128, 0, 200, 0, 128]),
        ])
        #expect(image.pixels == [100, 0, 100, 255, 0, 200, 0, 128, 0, 0, 0, 0])
    }

    @Test func passThroughDiffersFromIsolatedGroup() throws {
        func render(_ blend: String) throws -> [UInt8] {
            var multiply = Self.solid("M", 0, 0, 1, 1, [100, 100, 100, 255])
            multiply.blend = "mul "
            return try Self.render(1, 1, [Self.solid("Background", 0, 0, 1, 1, [200, 200, 200, 255])]
                + Self.group("G", blend: blend, [multiply])).pixels
        }
        #expect(try render("pass") == [78, 78, 78, 255])
        #expect(try render("norm") == [100, 100, 100, 255])
    }

    @Test func clippedLayerUsesBaseAlpha() throws {
        var clipped = Self.solid("Clipped", 0, 0, 2, 1, [0, 0, 255, 255])
        clipped.clipped = true
        var multiply = Self.solid("Multiply", 0, 0, 2, 1, [128, 128, 128, 255])
        multiply.blend = "mul "
        multiply.clipped = true
        let image = try Self.render(2, 1, [
            Self.solid("Background", 0, 0, 2, 1, [255, 255, 255, 255]),
            Self.solid("Base", 0, 0, 1, 1, [255, 0, 0, 255]),
            clipped, multiply,
        ])
        // The multiply works on the clipped blue inside the base, not on the white beside it.
        #expect(image.pixels == [0, 0, 128, 255, 255, 255, 255, 255])
    }

    @Test(arguments: [UInt8(0), 128]) func baseFillFadesOnlyTheBase(fill: UInt8) throws {
        var base = Self.solid("Base", 0, 0, 1, 1, [255, 0, 0, 255])
        base.blocks["iOpa"] = Data([fill, 0, 0, 0])
        var clipped = Self.solid("Clipped", 0, 0, 1, 1, [0, 0, 255, 255])
        clipped.clipped = true
        let image = try Self.render(1, 1, [Self.solid("Background", 0, 0, 1, 1, [255, 255, 255, 255]), base, clipped])
        #expect(image.pixels == [0, 0, 255, 255])
    }

    @Test func hiddenBaseHidesClipped() throws {
        var base = Self.solid("Base", 0, 0, 1, 1, [255, 0, 0, 255])
        base.hidden = true
        var clipped = Self.solid("Clipped", 0, 0, 2, 1, [0, 0, 255, 255])
        clipped.clipped = true
        let image = try Self.render(2, 1, [Self.solid("Background", 0, 0, 2, 1, [255, 255, 255, 255]), base, clipped])
        #expect(image.pixels == [255, 255, 255, 255, 255, 255, 255, 255])
    }

    @Test(arguments: [(UInt8(0), false), (255, false), (0, true)])
    func maskOutsideItsRectUsesDefaultColour(defaultColour: UInt8, disabled: Bool) throws {
        var layer = Self.solid("Red", 0, 0, 2, 1, [255, 0, 0, 255])
        layer.mask = Mask(rect: (0, 0, 1, 1), pixels: [255], defaultColour: defaultColour, disabled: disabled)
        let image = try Self.render(2, 1, [layer])
        let second: [UInt8] = defaultColour == 255 || disabled ? [255, 0, 0, 255] : [0, 0, 0, 0]
        #expect(image.pixels == [255, 0, 0, 255] + second)
    }

    @Test(arguments: ["norm", "pass"]) func groupOpacityAndMaskApplyOnce(blend: String) throws {
        let image = try Self.render(2, 1, Self.group("G", blend: blend, opacity: 128,
                                                     mask: Mask(rect: (0, 0, 1, 1), pixels: [255], defaultColour: 0), [
            Self.solid("Red", 0, 0, 2, 1, [255, 0, 0, 255]),
            Self.solid("Green", 0, 0, 2, 1, [0, 255, 0, 255]),
        ]))
        #expect(image.pixels == [0, 255, 0, 128, 0, 0, 0, 0])
    }

    @Test func blendIfDropsDarkSourcePixels() throws {
        let full: [UInt8] = [0, 0, 255, 255]
        var layer = Layer(name: "BW", rect: (0, 0, 1, 2), pixels: [0, 0, 0, 255, 255, 255, 255, 255])
        layer.blendIf = [128, 128, 255, 255] + full + Array([[UInt8]](repeating: full, count: 6).joined())
        let image = try Self.render(2, 1, [Self.solid("Background", 0, 0, 2, 1, [128, 128, 128, 255]), layer])
        #expect(image.pixels == [128, 128, 128, 255, 255, 255, 255, 255])
    }

    @Test func adjustmentHonoursBlendIf() throws {
        let full: [UInt8] = [0, 0, 255, 255]
        var invert = Layer(name: "Invert")
        // This Layer 0…128 on grey: only pixels the inversion leaves dark take it.
        invert.blendIf = [0, 0, 128, 128] + full + Array([[UInt8]](repeating: full, count: 6).joined())
        let image = try Self.render(2, 1, [
            Layer(name: "Background", rect: (0, 0, 1, 2), pixels: [250, 250, 250, 255, 10, 10, 10, 255]), invert,
        ]) { layer in
            layer.name != "Invert" ? nil : { image, _ in
                for p in 0..<image.width * image.height { for c in 0..<3 { image.pixels[p * 4 + c] = 255 - image.pixels[p * 4 + c] } }
            }
        }
        #expect(image.pixels == [5, 5, 5, 255, 10, 10, 10, 255])
    }

    @Test func emptyLayersAreSkipped() throws {
        let background = Self.solid("Background", 0, 0, 2, 2, [10, 20, 30, 255])
        var empty = Layer(name: "Empty", blend: "mul ")
        empty.opacity = 128
        let offCanvas = Self.solid("Off", 5, 5, 2, 2, [255, 0, 0, 255])
        let image = try Self.render(2, 2, [background, empty, offCanvas] + Self.group("G", blend: "norm", []))
        #expect(image == (try Self.render(2, 2, [background])))
    }

    @Test func scaledRenderMatchesFullRenderReduced() throws {
        func layer(_ name: String, _ rect: PSDFixture.Rect, alpha: UInt8, seed: UInt32) -> Layer {
            let n = (rect.bottom - rect.top) * (rect.right - rect.left)
            var pixels = PSDLayersTests.noise(n * 4, seed: seed)
            for p in 0..<n { pixels[p * 4 + 3] = alpha }
            return Layer(name: name, rect: rect, pixels: pixels)
        }
        let layers = [layer("A", (0, 0, 6, 8), alpha: 255, seed: 1), layer("B", (2, -2, 6, 4), alpha: 255, seed: 2),
                      layer("C", (0, 4, 4, 10), alpha: 100, seed: 3)]
        let full = try Self.render(8, 6, layers), half = try Self.render(8, 6, layers, scale: 0.5)
        #expect(half.width == 4 && half.height == 3)
        for y in 0..<3 {
            for x in 0..<4 {
                let points = [(0, 0), (1, 0), (0, 1), (1, 1)].map { ((y * 2 + $0.1) * 8 + x * 2 + $0.0) * 4 }
                let alpha = points.reduce(0) { $0 + Int(full.pixels[$1 + 3]) }
                for c in 0..<3 {
                    let mean = (points.reduce(0) { $0 + Int(full.pixels[$1 + c]) * Int(full.pixels[$1 + 3]) } + alpha / 2) / alpha
                    #expect(abs(mean - Int(half.pixels[(y * 4 + x) * 4 + c])) <= 2, "cell \(x), \(y)")
                }
                #expect(abs((alpha + 2) / 4 - Int(half.pixels[(y * 4 + x) * 4 + 3])) <= 2)
            }
        }
    }

    @Test func layerEdgeInsideAScaledCellComposesBeforeReducing() throws {
        // The layer covers half of the one half-scale cell, over a black and a white pixel: full size gives
        // black, black, so the cell is black, not grey.
        let layers = [Layer(name: "Background", rect: (0, 0, 1, 2), pixels: [0, 0, 0, 255, 255, 255, 255, 255]),
                      Self.solid("Edge", 0, 1, 1, 1, [0, 0, 0, 255])]
        #expect(try Self.render(2, 1, layers, scale: 0.5).pixels == [0, 0, 0, 255])
    }

    @Test func renderAboveThePixelCapStaysCloseToFullSizeReduced() throws {
        let layers = [Self.solid("Background", 0, 0, 8, 8, [200, 100, 50, 255]), Self.solid("Edge", 3, 3, 3, 3, [0, 0, 0, 255])]
        let file = try PSDLayersTests.open(PSDFixture.makeLayered(width: 8, height: 8, layers: layers))
        let capped = try PSDCompositor(file).render(scale: 0.25, maxPixels: 16), exact = try PSDCompositor(file).render(scale: 0.25)
        #expect(capped.width == 2 && capped.height == 2)
        for (a, b) in zip(capped.pixels, exact.pixels) { #expect(abs(Int(a) - Int(b)) <= 40) }
    }

    @Test func adjustmentHookRunsOnTheCanvasBelow() throws {
        var invert = Layer(name: "Invert")
        invert.mask = Mask(rect: (0, 0, 1, 2), pixels: [255, 0], defaultColour: 0)
        let image = try Self.render(3, 1, [
            Self.solid("Background", 0, 0, 3, 1, [10, 20, 30, 255]),
            invert,
            Self.solid("Above", 0, 2, 1, 1, [40, 50, 60, 255]),
        ]) { layer in
            layer.name != "Invert" ? nil : { image, _ in
                for p in 0..<image.width * image.height { for c in 0..<3 { image.pixels[p * 4 + c] = 255 - image.pixels[p * 4 + c] } }
            }
        }
        #expect(image.pixels == [245, 235, 225, 255, 10, 20, 30, 255, 40, 50, 60, 255])
    }
}
