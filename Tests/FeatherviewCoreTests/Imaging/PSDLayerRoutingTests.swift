import CoreGraphics
import Foundation
import ImageIO
import os
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
    /// Display decodes of a huge canvas draw at most `maxPixels`; a full-size decode (batch, Save As) draws every pixel,
    /// or fails when even that is out of reach, never smaller.
    @Test func hugeCanvasDrawsSmallerOnlyOnScreen() throws {
        let width = 900, height = 800
        let layers = [Self.layers(width, height)[0], PSDCompositorTests.solid("Red", 0, 0, 4, 4, [220, 20, 20, 255])]
        let url = try Self.write(PSDFixture.makeLayered(width: width, height: height, layers: layers, realComposite: false))
        try PSDCompositor.$maxPixels.withValue(500_000) {
            let screen = try ImageDecoder.decode(url, fitting: [PixelSize(width: 4000, height: 4000)])
            #expect(screen.width * screen.height <= 500_000 + screen.width + screen.height)
            #expect(screen.width > 600 && abs(Double(screen.width) / Double(screen.height) - 9.0 / 8) < 0.01)
            #expect(try #require(RGBAImage(screen))[screen.width / 2, screen.height / 2] == (0, 128, 255, 255))
            let full = try ImageDecoder.decode(url)
            #expect(full.width == width && full.height == height)
            #expect(try #require(RGBAImage(full))[width / 2, height / 2] == (0, 128, 255, 255))
            #expect(try ImageDecoder.decode(url, maxPixelSize: 850).width == 850)
        }
        try PSDCompositor.$maxPixels.withValue(100_000) {
            #expect(throws: DecodeError.self) { try ImageDecoder.decode(url) }
        }
    }

    /// A display decode draws small enough that every canvas the compositor holds at once (copies for nested
    /// pass-through groups below full fill, a fill layer, the picture) fits `memoryBudget`.
    @Test func displayDecodeKeepsLiveCanvasesWithinTheBudget() throws {
        let width = 600, height = 400
        var dodge = PSDCompositorTests.solid("Dodge", 0, 0, width, height, [50, 60, 70, 200])
        dodge.blend = "lddg"
        var nested = [dodge]
        for level in 0..<4 {
            nested = PSDCompositorTests.group("P\(level)", blend: "pass", nested)
            nested[nested.count - 1].blocks["iOpa"] = Data([200])
        }
        let url = try Self.write(PSDFixture.makeLayered(width: width, height: height, layers: Self.layers(width, height) + nested,
                                                        realComposite: false))
        let budget = 4 << 20, live = OSAllocatedUnfairLock(initialState: (now: 0, peak: 0))
        let image = try PSDCompositor.$memoryBudget.withValue(budget) {
            try PSDCompositor.$liveBytes.withValue(live) { try ImageDecoder.decode(url, fitting: [PixelSize(width: 4000, height: 4000)]) }
        }
        let peak = live.withLock { $0.peak }
        #expect(peak > 0 && peak <= budget, "\(peak)")
        #expect(image.width < width && abs(Double(image.width) / Double(image.height) - 1.5) < 0.02)
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

    /// Layers clipped to an adjustment layer draw over what it adjusted, inside its mask.
    @Test func layersClipToAdjustments() throws {
        let fill = Layer(name: "Fill", blocks: ["SoCo": PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(255, 128, 0))])])
        let invert = Layer(name: "Invert", mask: .init(rect: (0, 0, 2, 2), pixels: [255, 255, 255, 255]), blocks: ["nvrt": Data()])
        var again = Layer(name: "Invert again", blocks: ["nvrt": Data()])
        again.clipped = true
        var red = PSDCompositorTests.solid("Red", 0, 1, 3, 2, [255, 0, 0, 255])
        red.clipped = true
        func render(_ clipped: Layer) throws -> RGBAImage {
            let url = try Self.write(PSDFixture.makeLayered(width: 4, height: 2, layers: [fill, invert, clipped], realComposite: false))
            return try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
        }
        let twice = try render(again), covered = try render(red)
        #expect(twice[0, 0] == (255, 128, 0, 255))   // inverted twice inside the mask
        #expect(twice[3, 1] == (255, 128, 0, 255))
        #expect(covered[1, 0] == (255, 0, 0, 255))   // red inside the mask
        #expect(covered[0, 1] == (0, 127, 255, 255))  // inverted, not under the red
        #expect(covered[3, 1] == (255, 128, 0, 255))  // outside the mask: neither
    }

    /// A mask record whose parameters (flags bit 16) give the user mask's (2) or the vector mask's (8) feather.
    static func featherRecord(_ rect: (Int32, Int32, Int32, Int32), flags: UInt8, parameter: UInt8, _ radius: Double) -> [UInt8] {
        func be<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.bigEndian, Array.init) }
        let body = be(rect.0) + be(rect.1) + be(rect.2) + be(rect.3) + [0, flags | 16, parameter] + be(radius.bitPattern) + [0]
        return be(UInt32(body.count)) + body
    }

    /// A feathered mask softens its edge by a Gaussian of the feather's radius; a feathered vector mask its path's.
    @Test func featheredMasksBlurTheirEdge() throws {
        var masked = PSDCompositorTests.solid("Red", 0, 0, 16, 16, [255, 0, 0, 255])
        masked.mask = .init(rect: (0, 0, 16, 8), pixels: [UInt8](repeating: 255, count: 128))
        masked.maskRecord = Self.featherRecord((0, 0, 16, 8), flags: 0, parameter: 2, 2)
        var shaped = PSDCompositorTests.solid("Red", 0, 0, 16, 16, [255, 0, 0, 255])
        shaped.blocks["vmsk"] = PSDFillsTests.vectorMask([(0, 0), (0.5, 0), (0.5, 1), (0, 1)])
        shaped.maskRecord = Self.featherRecord((0, 0, 0, 0), flags: 8, parameter: 8, 2)
        for layer in [masked, shaped] {
            let url = try Self.write(PSDFixture.makeLayered(width: 16, height: 16, layers: [layer], realComposite: false))
            let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
            // Half a pixel from the edge at x = 8: the normal distribution's 0.6 and 0.4 of it.
            #expect((145...162).contains(Int(image[7, 8].a)), "\(image[7, 8])")
            #expect((93...110).contains(Int(image[8, 8].a)), "\(image[8, 8])")
            #expect(image[3, 8].a >= 235 && image[12, 8].a <= 5)
        }
    }

    /// A pass-through group that is a clipping base still passes its blend modes through, inside its own content: an
    /// adjustment alone in it has no content, so it changes nothing.
    @Test func passThroughClippingBaseBlendsInsideItsContent() throws {
        let grey = Layer(name: "Grey", blocks: ["SoCo": PSDFillsTests.block([("Clr ", PSDFillsTests.rgb(100, 100, 100))])])
        var dodge = PSDCompositorTests.solid("Dodge", 0, 0, 2, 2, [50, 50, 50, 255])
        dodge.blend = "lddg"
        var empty = Layer(name: "Empty")
        empty.clipped = true
        let invert = Layer(name: "Invert", blocks: ["nvrt": Data()])
        for (child, expected) in [(dodge, UInt8(150)), (invert, UInt8(100))] {
            let layers = [grey] + PSDCompositorTests.group("G", blend: "pass", [child]) + [empty]
            let url = try Self.write(PSDFixture.makeLayered(width: 2, height: 2, layers: layers, realComposite: false))
            let image = try PSDCompositor.photoshop(try #require(try PSDLayers(url: url))).render(scale: 1)
            #expect(image[1, 1] == (expected, expected, expected, 255))
        }
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
