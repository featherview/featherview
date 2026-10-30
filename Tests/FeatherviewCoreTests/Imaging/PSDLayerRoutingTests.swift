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
