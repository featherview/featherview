import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImagePipelineTests {
    let context = PipelineContext(values: TextValues(name: "IMG_1", folder: "Holiday", date: "2024-05-01", index: 1))

    func cg(_ image: CIImage) throws -> CGImage { try PipelineRender.cgImage(image) }

    func colours(_ image: CGImage) throws -> Set<[UInt8]> {
        let rgba = try #require(RGBAImage(image))
        return Set(stride(from: 0, to: rgba.pixels.count, by: 4).map { Array(rgba.pixels[$0..<$0 + 4]) })
    }

    @Test func noOperationsKeepsPixels() throws {
        let input = try cg(PipelineFixtures.quadrants(width: 8, height: 8))
        let output = try ImagePipeline.apply(input, BatchSettings(), context: context)
        #expect(RGBAImage(output) == RGBAImage(input))
    }

    @Test func specOrderCropThenResize() throws {
        var s = BatchSettings()
        s.crop.isOn = true
        s.crop.width = 100; s.crop.height = 100
        s.resize.isOn = true
        s.resize.mode = .longestSide; s.resize.side = 50
        let output = try ImagePipeline.apply(try cg(PipelineFixtures.quadrants(width: 400, height: 400)), s, context: context)
        #expect((output.width, output.height) == (50, 50))
        #expect(try colours(output) == [[255, 0, 0, 255]])  // the red quadrant only: cropped first
    }

    @Test func rotateAfterResize() throws {
        var s = BatchSettings()
        s.resize.isOn = true
        s.resize.mode = .widthHeight; s.resize.width = 200
        s.orientation.rotate = .right
        let output = try ImagePipeline.apply(try cg(PipelineFixtures.solid(.white, width: 400, height: 100)), s, context: context)
        #expect((output.width, output.height) == (50, 200))
    }

    @Test func canvasThenBorderThenText() throws {
        var s = BatchSettings()
        s.canvas.isOn = true  // 10 px per side
        s.border.isOn = true
        s.border.outerWidth = 5
        s.text.isOn = true
        s.text.placement = .stripBelow
        let output = try ImagePipeline.apply(try cg(PipelineFixtures.solid(.black, width: 100, height: 50)), s, context: context)
        #expect(output.width == 130)
        #expect(output.height > 80)  // 50 + 20 canvas + 10 border, then the text strip
    }

    @Test func reduceColoursIsLast() throws {
        var s = BatchSettings()
        s.colour.isOn = true
        s.colour.reduceColours = 2
        s.colour.dither = false
        s.text.isOn = true
        s.text.sizePercent = 20
        s.text.colour = RGBAColor(red: 0.2, green: 0.9, blue: 0.4)
        let output = try ImagePipeline.apply(try cg(PipelineFixtures.solid(.white, width: 200, height: 100)), s, context: context)
        // Anti-aliased text has many colours; reduced after it, at most two are left.
        #expect(try colours(output).count <= 2)
    }

    @Test func scaleShrinksPixelSettings() throws {
        var s = BatchSettings()
        s.border.isOn = true
        s.border.outerWidth = 10
        var preview = context
        preview.scale = 0.5
        let output = try ImagePipeline.apply(try cg(PipelineFixtures.solid(.black, width: 100, height: 100)), s, context: preview)
        #expect((output.width, output.height) == (110, 110))
    }

    @Test func canvasLeavingNothingThrows() throws {
        var s = BatchSettings()
        s.canvas.isOn = true
        s.canvas.left = -100
        #expect(throws: CanvasError.nothingLeft) {
            try ImagePipeline.apply(try cg(PipelineFixtures.solid(.black, width: 50, height: 50)), s, context: context)
        }
    }
}
