import Testing
@testable import FeatherviewCore

@Suite struct LayerCanvasTests {
    static func close(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (UInt8, UInt8, UInt8, UInt8), within d: Int = 0) -> Bool {
        abs(Int(a.r) - Int(b.0)) <= d && abs(Int(a.g) - Int(b.1)) <= d && abs(Int(a.b) - Int(b.2)) <= d && abs(Int(a.a) - Int(b.3)) <= d
    }

    @Test func opaqueLayerReplaces() throws {
        var canvas = try LayerCanvas(width: 2, height: 2)
        canvas.draw(Fixtures.solid(2, 2, (0, 0, 255, 255)), x: 0, y: 0, opacity: 1)
        canvas.draw(Fixtures.solid(2, 2, (10, 20, 30, 255)), x: 0, y: 0, opacity: 1)
        #expect(canvas.image == Fixtures.solid(2, 2, (10, 20, 30, 255)))
    }

    @Test func halfOpaqueOverTransparent() throws {
        var canvas = try LayerCanvas(width: 1, height: 1)
        canvas.draw(Fixtures.solid(1, 1, (255, 0, 0, 255)), x: 0, y: 0, opacity: 0.5)
        #expect(canvas.image[0, 0] == (255, 0, 0, 128))
    }

    @Test func halfOpaqueOverWhite() throws {
        var canvas = try LayerCanvas(width: 1, height: 1)
        canvas.draw(Fixtures.solid(1, 1, (255, 255, 255, 255)), x: 0, y: 0, opacity: 1)
        canvas.draw(Fixtures.solid(1, 1, (255, 0, 0, 255)), x: 0, y: 0, opacity: 0.5)
        #expect(Self.close(canvas.image[0, 0], (255, 128, 128, 255), within: 1))
    }

    @Test func layerAlphaTimesOpacity() throws {
        var canvas = try LayerCanvas(width: 1, height: 1)
        canvas.draw(Fixtures.solid(1, 1, (0, 255, 0, 128)), x: 0, y: 0, opacity: 0.5)
        #expect(Self.close(canvas.image[0, 0], (0, 255, 0, 64), within: 1))
    }

    @Test func zeroOpacityLeavesCanvas() throws {
        var canvas = try LayerCanvas(width: 2, height: 1)
        canvas.draw(Fixtures.solid(2, 1, (1, 2, 3, 200)), x: 0, y: 0, opacity: 1)
        let before = canvas.image
        canvas.draw(Fixtures.solid(2, 1, (255, 255, 255, 255)), x: 0, y: 0, opacity: 0)
        #expect(canvas.image == before)
    }

    @Test func clipsLayersOutsideTheCanvas() throws {
        let red: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
        let clear: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        func drawn(_ layer: RGBAImage, _ x: Int, _ y: Int) throws -> RGBAImage {
            var canvas = try LayerCanvas(width: 4, height: 3)
            canvas.draw(layer, x: x, y: y, opacity: 1)
            return canvas.image
        }
        let square = Fixtures.solid(3, 3, red)

        let topLeft = try drawn(square, -2, -1)
        for y in 0..<3 { for x in 0..<4 { #expect(topLeft[x, y] == ((x < 1 && y < 2) ? red : clear)) } }

        let rightEdge = try drawn(square, 3, 0)
        for y in 0..<3 { for x in 0..<4 { #expect(rightEdge[x, y] == (x == 3 ? red : clear)) } }

        #expect(try drawn(square, 1000, 1000) == Fixtures.solid(4, 3, clear))
        #expect(try drawn(square, -1000, -1000) == Fixtures.solid(4, 3, clear))
        #expect(try drawn(Fixtures.solid(10, 10, red), -3, -3) == Fixtures.solid(4, 3, red))
    }

    @Test func canvasRefusesHugeSizes() {
        #expect(throws: OwnDecodeError.corrupt) { try LayerCanvas(width: 70000, height: 10) }
    }
}

@Suite struct SampleCorpusTests {
    @Test func corpusDifferenceComparesOverWhite() {
        let image = Fixtures.solid(3, 2, (10, 200, 30, 128))
        #expect(SampleCorpus.difference(image, image) == 0)
        #expect(SampleCorpus.difference(image, Fixtures.solid(2, 3, (10, 200, 30, 128))) == .infinity)
        // Fully transparent pixels of any colour look the same over white.
        #expect(SampleCorpus.difference(Fixtures.solid(1, 1, (0, 0, 0, 0)), Fixtures.solid(1, 1, (255, 9, 9, 0))) == 0)
    }
}
