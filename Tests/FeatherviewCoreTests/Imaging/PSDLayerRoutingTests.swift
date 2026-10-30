import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct PSDLayerRoutingTests {
    typealias Layer = PSDFixture.FixtureLayer

    /// Over a white stored composite: a blue solid colour fill layer (which ImageIO doesn't draw), a red layer over
    /// the left half and a half-transparent blue one over the bottom row.
    static func layers(_ width: Int, _ height: Int) -> [Layer] {
        [
            Layer(name: "Fill", blocks: ["SoCo": PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(0, 128, 255))])]),
            PSDCompositorTests.solid("Red", 0, 0, width / 2, height, [220, 20, 20, 255]),
            PSDCompositorTests.solid("Blue", height - 1, 0, width, 1, [0, 0, 200, 128]),
        ]
    }

    static func write(_ data: Data, name: String = "a.psd") throws -> URL {
        let url = try Fixtures.makeTempDir().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test func fileWithoutCompositeRendersItsLayers() throws {
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 6, layers: Self.layers(8, 6), realComposite: false))
        let decoded = try #require(RGBAImage(try ImageDecoder.decode(url)))
        let layers = try #require(try PSDLayers(url: url))
        let expected = try PSDCompositor.photoshop(layers).render(scale: 1)
        #expect(decoded.width == 8 && decoded.height == 6)
        for y in 0..<6 {
            for x in 0..<8 {
                let a = decoded[x, y], b = expected[x, y]
                #expect(abs(Int(a.r) - Int(b.r)) <= 1 && abs(Int(a.g) - Int(b.g)) <= 1 && abs(Int(a.b) - Int(b.b)) <= 1
                        && abs(Int(a.a) - Int(b.a)) <= 1, "(\(x), \(y)): \(a) vs \(b)")
            }
        }
        #expect(decoded[0, 0] == (220, 20, 20, 255))
        #expect(decoded[7, 0] == (0, 128, 255, 255))
        #expect(!ImageDecoder.readsRegions(url))
    }

    @Test func fileWithCompositeKeepsIt() throws {
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 6, layers: Self.layers(8, 6), realComposite: true))
        let decoded = try #require(RGBAImage(try ImageDecoder.decode(url)))
        // The stored composite is white everywhere; the layers are red and blue.
        #expect(decoded[0, 0] == (255, 255, 255, 255))
        #expect(decoded[7, 5] == (255, 255, 255, 255))
    }

    @Test func fitDecodeIsExactSize() throws {
        let url = try Self.write(PSDFixture.makeLayered(width: 400, height: 200, layers: Self.layers(400, 200), realComposite: false))
        let image = try ImageDecoder.decode(url, halvingSteps: true, fitting: [PixelSize(width: 100, height: 100)])
        #expect(image.width == 100 && image.height == 50)
        let pixels = try #require(RGBAImage(image))
        #expect(pixels[10, 10].r > 200 && pixels[10, 10].g < 40)
        let thumbnail = try ImageDecoder.thumbnail(url, side: 64, colorSpace: nil)
        #expect(thumbnail.width == 64 && thumbnail.height == 32)
        #expect(try #require(RGBAImage(thumbnail))[5, 5].g < 40)
        #expect(try #require(RGBAImage(thumbnail))[60, 5] == (0, 128, 255, 255))
    }

    @Test func damagedLayersFallBack() throws {
        var layers = Self.layers(8, 6)
        // A zip channel that inflates short: the layers parse, the render throws.
        layers[1].override[0] = [0, 2] + PSDFixture.zlib([1, 2, 3])
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 6, layers: layers, realComposite: false))
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let raw = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let imageIO = try #require(RGBAImage(raw))
        #expect(image.width == 8 && image.height == 6 && image == imageIO)
    }

    /// A full-size decode of a canvas too large to draw at that size draws the layers at the largest size it may
    /// (ImageIO would show another picture: it draws no fill layers); the fit decode draws them too.
    @Test func hugeCanvasAtFullSizeDrawsSmaller() throws {
        let width = 900, height = 800
        let layers = [Self.layers(width, height)[0], PSDCompositorTests.solid("Red", 0, 0, 4, 4, [220, 20, 20, 255])]
        let url = try Self.write(PSDFixture.makeLayered(width: width, height: height, layers: layers, realComposite: false))
        try PSDCompositor.$maxPixels.withValue(500_000) {
            let fit = try #require(RGBAImage(try ImageDecoder.decode(url, maxPixelSize: 200)))
            #expect(fit[fit.width / 2, fit.height / 2] == (0, 128, 255, 255))
            let full = try ImageDecoder.decode(url)
            #expect(full.width * full.height <= 500_000 + full.width + full.height)
            #expect(full.width > 600 && abs(Double(full.width) / Double(full.height) - 9.0 / 8) < 0.01)
            let pixels = try #require(RGBAImage(full))
            #expect(pixels[full.width / 2, full.height / 2] == (0, 128, 255, 255))
        }
    }

    /// A file that can't be opened for a moment draws its layers again once it can: only damage is remembered.
    @Test func unreadableFileDrawsLayersOnceReadable() throws {
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 6, layers: Self.layers(8, 6), realComposite: false))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        #expect(throws: (any Error).self) { try ImageDecoder.decode(url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try #require(RGBAImage(try ImageDecoder.decode(url)))[7, 0] == (0, 128, 255, 255))
    }

    @Test func sixteenBitStaysWithImageIO() throws {
        let pixels = PSDRoutingTests.gradient(width: 20, height: 10)
        let url = try Self.write(PSDFixture.make(width: 20, height: 10, pixels: pixels, realMerged: false, depth: 16))
        #expect(try PSDLayers(url: url) == nil)
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 20 && image.height == 10)
    }

    /// The hooks: a solid colour fill layer, then an invert adjustment over the left half through its mask.
    @Test func photoshopDrawsFillsAndAdjustments() throws {
        let fill = Layer(name: "Fill", blocks: ["SoCo": PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(255, 128, 0))])])
        let invert = Layer(name: "Invert", mask: .init(rect: (0, 0, 2, 2), pixels: [255, 255, 255, 255]), blocks: ["nvrt": Data()])
        let url = try Self.write(PSDFixture.makeLayered(width: 4, height: 2, layers: [fill, invert], realComposite: false))
        let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
        #expect(image[0, 0] == (0, 127, 255, 255))
        #expect(image[3, 1] == (255, 128, 0, 255))
    }

    /// A vector mask limits an adjustment layer to its path, with the layer mask.
    @Test func vectorMaskLimitsAdjustments() throws {
        let fill = Layer(name: "Fill", blocks: ["SoCo": PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(255, 128, 0))])])
        var invert = Layer(name: "Invert", mask: .init(rect: (0, 0, 2, 6), pixels: [UInt8](repeating: 255, count: 12)),
                           blocks: ["nvrt": Data()])
        invert.blocks["vmsk"] = PSDFillsTests.vectorMask([(0, 0), (0.5, 0), (0.5, 1), (0, 1)])
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 2, layers: [fill, invert], realComposite: false))
        let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
        #expect(image[0, 0] == (0, 127, 255, 255))  // inside both masks
        #expect(image[5, 0] == (255, 128, 0, 255))  // inside the layer mask, outside the path
        #expect(image[7, 1] == (255, 128, 0, 255))  // outside both
    }

    /// A group's vector mask cuts what the group draws, pass-through or not; below full density it only fades it.
    @Test(arguments: [("pass", 255), ("norm", 255), ("pass", 128)])
    func vectorMaskCutsGroups(blend: String, density: Int) throws {
        var layers = [PSDCompositorTests.solid("Blue", 0, 0, 8, 2, [0, 0, 255, 255])]
            + PSDCompositorTests.group("G", blend: blend, [PSDCompositorTests.solid("Red", 0, 0, 8, 2, [255, 0, 0, 255])])
        layers[layers.count - 1].blocks["vmsk"] = PSDFillsTests.vectorMask([(0, 0), (0.5, 0), (0.5, 1), (0, 1)])
        if density < 255 {
            // A 20-byte record of the vector mask's rendering, parameters (vector mask density) in place of the padding.
            layers[layers.count - 1].maskRecord = [0, 0, 0, 20] + [UInt8](repeating: 0, count: 16) + [0, 0x18, 4, UInt8(density)]
        }
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 2, layers: layers, realComposite: false))
        let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
        #expect(image[0, 0] == (255, 0, 0, 255))
        #expect(image[7, 1] == (density == 255 ? (0, 0, 255, 255) : (127, 0, 128, 255)))
    }

    /// A stroked shape layer shows its stored pixels whole: an outside stroke lies beyond the path.
    @Test func strokedShapeKeepsItsPixels() throws {
        var layer = PSDCompositorTests.solid("A", 0, 0, 8, 8, [10, 200, 10, 255])
        layer.blocks["vmsk"] = PSDFillsTests.vectorMask(PSDFillsTests.square(0.5, 1))
        layer.blocks["vstk"] = Data([0, 0, 0, 16])
        var filled = layer
        filled.blocks["SoCo"] = PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(255, 0, 0))])
        for layer in [layer, filled] {
            let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 8, layers: [layer], realComposite: false))
            let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
            #expect(image[1, 1] == (10, 200, 10, 255))
        }
    }

    /// A vector mask cuts a pixel layer too.
    @Test func vectorMaskCutsPixelLayers() throws {
        var layer = PSDCompositorTests.solid("A", 0, 0, 8, 8, [10, 200, 10, 255])
        layer.blocks["vmsk"] = PSDFillsTests.vectorMask(PSDFillsTests.square(0.5, 1))
        let url = try Self.write(PSDFixture.makeLayered(width: 8, height: 8, layers: [layer], realComposite: false))
        let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
        #expect(image[1, 1].a == 0)
        #expect(image[6, 6] == (10, 200, 10, 255))
    }
}
