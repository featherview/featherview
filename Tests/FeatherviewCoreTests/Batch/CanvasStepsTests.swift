import CoreImage
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct CanvasStepsTests {
    private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    private let red = RGBAColor(red: 1, green: 0, blue: 0)

    private func close(_ a: Pixel, _ b: (Int, Int, Int, Int)) -> Bool {
        abs(Int(a.r) - b.0) <= 1 && abs(Int(a.g) - b.1) <= 1 && abs(Int(a.b) - b.2) <= 1 && abs(Int(a.a) - b.3) <= 1
    }

    private func perSide(_ left: Int, _ right: Int, _ top: Int, _ bottom: Int,
                         colour: RGBAColor = .black) -> CanvasSettings {
        var s = CanvasSettings()
        s.isOn = true
        s.method = .perSide
        s.left = left; s.right = right; s.top = top; s.bottom = bottom
        s.colour = colour
        return s
    }

    private func totalSize(_ width: Int, _ height: Int, _ anchor: ImageAnchor) -> CanvasSettings {
        var s = CanvasSettings()
        s.isOn = true
        s.method = .totalSize
        s.width = width; s.height = height; s.anchor = anchor
        return s
    }

    private func ratio(_ width: Double, _ height: Double) -> CanvasSettings {
        var s = CanvasSettings()
        s.isOn = true
        s.method = .aspectRatio
        s.ratioWidth = width; s.ratioHeight = height
        return s
    }

    /// A `width × height` white canvas with a red rectangle; `noise` darkens the white by up to 5.
    private func framed(width: Int, height: Int, picture: CGRect, noise: Bool = false) -> CIImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                if picture.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    image[x, y] = (255, 0, 0, 255)
                } else {
                    let v = UInt8(255 - (noise ? (x * 7 + y * 3) % 6 : 0))
                    image[x, y] = (v, v, v, 255)
                }
            }
        }
        return PipelineFixtures.fromRGBA(image)
    }

    // MARK: Canvas

    @Test func perSideAddsAndPlaces() throws {
        let out = try CanvasStep.apply(PipelineFixtures.quadrants(width: 10, height: 10), perSide(2, 3, 4, 1), scale: 1)
        let p = try PipelineFixtures.pixels(out)
        #expect(p.width == 15 && p.height == 15)
        #expect(close(p[2, 4], (255, 0, 0, 255)))
        #expect(close(p[1, 4], (0, 0, 0, 255)))
        #expect(close(p[2, 3], (0, 0, 0, 255)))
        #expect(close(p[11, 13], (255, 255, 255, 255)))
        #expect(close(p[12, 13], (0, 0, 0, 255)))
        #expect(close(p[11, 14], (0, 0, 0, 255)))
    }

    @Test func negativeSideCutsIn() throws {
        let out = try CanvasStep.apply(PipelineFixtures.quadrants(width: 10, height: 10), perSide(-5, 0, -5, 0), scale: 1)
        let p = try PipelineFixtures.pixels(out)
        #expect(p.width == 5 && p.height == 5)
        #expect(close(p[0, 0], (255, 255, 255, 255)))
        #expect(close(p[4, 4], (255, 255, 255, 255)))
    }

    @Test func negativeBorderLargerThanImageFails() {
        #expect(throws: CanvasError.nothingLeft) {
            try CanvasStep.apply(PipelineFixtures.solid(red, width: 10, height: 10), perSide(-6, -6, 0, 0), scale: 1)
        }
        #expect(throws: CanvasError.nothingLeft) {
            try CanvasStep.apply(PipelineFixtures.solid(red, width: 10, height: 10), perSide(0, 0, -20, 0), scale: 1)
        }
    }

    @Test func totalSizeAtEachAnchor() throws {
        let expected: [ImageAnchor: (Int, Int)] = [
            .topLeft: (0, 0), .top: (3, 0), .topRight: (6, 0),
            .left: (0, 3), .center: (3, 3), .right: (6, 3),
            .bottomLeft: (0, 6), .bottom: (3, 6), .bottomRight: (6, 6),
        ]
        for anchor in ImageAnchor.allCases {
            let out = try CanvasStep.apply(PipelineFixtures.solid(red, width: 4, height: 4),
                                           totalSize(10, 10, anchor), scale: 1)
            let p = try PipelineFixtures.pixels(out)
            let (x, y) = expected[anchor]!
            #expect(p.width == 10 && p.height == 10)
            #expect(close(p[x, y], (255, 0, 0, 255)), "\(anchor)")
            #expect(close(p[x + 3, y + 3], (255, 0, 0, 255)), "\(anchor)")
            if x > 0 { #expect(close(p[x - 1, y], (0, 0, 0, 255)), "\(anchor)") }
            if y > 0 { #expect(close(p[x, y - 1], (0, 0, 0, 255)), "\(anchor)") }
            if x + 4 < 10 { #expect(close(p[x + 4, y], (0, 0, 0, 255)), "\(anchor)") }
            if y + 4 < 10 { #expect(close(p[x, y + 4], (0, 0, 0, 255)), "\(anchor)") }
        }
    }

    @Test func totalSizeZeroKeepsThatSide() throws {
        let image = PipelineFixtures.solid(red, width: 10, height: 6)
        let wide = try CanvasStep.apply(image, totalSize(20, 0, .center), scale: 1)
        #expect(wide.extent == CGRect(x: 0, y: 0, width: 20, height: 6))
        let tall = try CanvasStep.apply(image, totalSize(0, 9, .center), scale: 1)
        #expect(tall.extent == CGRect(x: 0, y: 0, width: 10, height: 9))
    }

    @Test func totalSizeSmallerCrops() throws {
        let image = PipelineFixtures.quadrants(width: 10, height: 10)
        let topLeft = try PipelineFixtures.pixels(CanvasStep.apply(image, totalSize(5, 5, .topLeft), scale: 1))
        #expect(topLeft.width == 5 && topLeft.height == 5)
        #expect(close(topLeft[0, 0], (255, 0, 0, 255)) && close(topLeft[4, 4], (255, 0, 0, 255)))
        let bottomRight = try PipelineFixtures.pixels(CanvasStep.apply(image, totalSize(5, 5, .bottomRight), scale: 1))
        #expect(close(bottomRight[0, 0], (255, 255, 255, 255)) && close(bottomRight[4, 4], (255, 255, 255, 255)))
    }

    @Test func aspectRatioSixteenNine() throws {
        let out = try CanvasStep.apply(PipelineFixtures.solid(red, width: 1000, height: 1000), ratio(16, 9), scale: 1)
        #expect(abs(out.extent.width - 1778) <= 1 && out.extent.height == 1000)
        #expect(out.extent.origin == .zero)
    }

    @Test func aspectRatioPortrait() throws {
        let square = try CanvasStep.apply(PipelineFixtures.solid(red, width: 1000, height: 1000), ratio(9, 16), scale: 1)
        #expect(square.extent.width == 1000 && abs(square.extent.height - 1778) <= 1)
        let wide = try CanvasStep.apply(PipelineFixtures.solid(red, width: 200, height: 100), ratio(1, 2), scale: 1)
        #expect(wide.extent == CGRect(x: 0, y: 0, width: 200, height: 400))
        let unchanged = try CanvasStep.apply(PipelineFixtures.solid(red, width: 200, height: 100), ratio(0, 2), scale: 1)
        #expect(unchanged.extent == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func clearColourIsTransparent() throws {
        let out = try CanvasStep.apply(PipelineFixtures.solid(red, width: 4, height: 4),
                                       perSide(2, 2, 2, 2, colour: .clear), scale: 1)
        let p = try PipelineFixtures.pixels(out)
        #expect(p.width == 8 && p.height == 8)
        #expect(p[0, 0].a == 0)
        #expect(close(p[2, 2], (255, 0, 0, 255)))
    }

    @Test func canvasScalesWithPreview() throws {
        let out = try CanvasStep.apply(PipelineFixtures.solid(red, width: 10, height: 10), perSide(4, 4, 4, 4), scale: 0.5)
        let p = try PipelineFixtures.pixels(out)
        #expect(p.width == 14 && p.height == 14)
        #expect(close(p[1, 1], (0, 0, 0, 255)))
        #expect(close(p[2, 2], (255, 0, 0, 255)))
    }

    // MARK: Auto-crop

    @Test func autoCropRemovesUniformBorders() throws {
        let image = framed(width: 40, height: 30, picture: CGRect(x: 5, y: 3, width: 20, height: 20))
        let p = try PipelineFixtures.pixels(AutoCropStep.apply(image))
        #expect(p.width == 20 && p.height == 20)
        #expect(close(p[0, 0], (255, 0, 0, 255)) && close(p[19, 19], (255, 0, 0, 255)))
    }

    @Test func autoCropKeepsUniformImage() throws {
        let out = AutoCropStep.apply(PipelineFixtures.solid(red, width: 30, height: 20))
        #expect(out.extent == CGRect(x: 0, y: 0, width: 30, height: 20))
    }

    @Test func autoCropToleratesJPEGNoise() throws {
        let image = framed(width: 40, height: 30, picture: CGRect(x: 5, y: 3, width: 20, height: 20), noise: true)
        let out = AutoCropStep.apply(image)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test func autoCropMapsBackFromTheSmallCopy() throws {
        let image = framed(width: 2400, height: 1600, picture: CGRect(x: 600, y: 400, width: 1200, height: 800))
        let out = AutoCropStep.apply(image)
        #expect(out.extent.origin == .zero)
        #expect(out.extent.size == CGSize(width: 1200, height: 800))
    }

    /// Large images take the shrunk path; noise of ±5 around the corner colour is still border.
    @Test func autoCropToleratesNoiseAroundTheCornerOnLargeImages() throws {
        let picture = CGRect(x: 600, y: 400, width: 1200, height: 800)
        var image = RGBAImage(width: 2400, height: 1600)
        for y in 0..<1600 {
            for x in 0..<2400 {
                let v = UInt8(245 + ((x * 7 + y * 3 + 5) % 11 - 5))  // 245 at the corners
                image[x, y] = picture.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) ? (255, 0, 0, 255) : (v, v, v, 255)
            }
        }
        #expect(AutoCropStep.apply(PipelineFixtures.fromRGBA(image)).extent == CGRect(x: 0, y: 0, width: 1200, height: 800))
    }

    /// The shrunk pass must judge against the corner pixel itself, or it can run past the real edge.
    @Test func autoCropLargeImageUsesTheCornerPixel() throws {
        var image = RGBAImage(width: 2400, height: 1600)
        for y in 0..<1600 {
            for x in 0..<2400 {
                let v: UInt8 = y < 10 ? 200 : y < 400 ? 186 : UInt8((x * 13) % 256)
                image[x, y] = (v, v, v, 255)
            }
        }
        image[1, 1] = (192, 192, 192, 255)  // darkens the corner block's minimum, not the corner pixel
        #expect(AutoCropStep.apply(PipelineFixtures.fromRGBA(image)).extent == CGRect(x: 0, y: 0, width: 2400, height: 1590))
    }

    /// Shrinking must not average a thin, faint line near the edge into the border and cut it off.
    @Test(arguments: [100, 104, 106])
    func autoCropKeepsThinLineNearTheEdge(x: Int) throws {
        func box(_ v: CGFloat, _ r: CGRect) -> CIImage {
            CIImage(color: CIColor(red: v, green: v, blue: v, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!).cropped(to: r)
        }
        let image = box(230.0 / 255, CGRect(x: x, y: 0, width: 1, height: 400))
            .composited(over: PipelineFixtures.solid(red, width: 3000, height: 400).transformed(by: .init(translationX: 1500, y: 0)))
            .composited(over: box(1, CGRect(x: 0, y: 0, width: 6000, height: 400)))
        let out = AutoCropStep.apply(image)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 4500 - x, height: 400))
    }

    @Test func autoCropKeepsThinLineNearTheBottom() throws {
        let grey = CIColor(red: 0.9, green: 0.9, blue: 0.9, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        // Core Image's y = 3 is the fourth row from the bottom.
        let image = CIImage(color: grey).cropped(to: CGRect(x: 0, y: 3, width: 400, height: 1))
            .composited(over: PipelineFixtures.solid(red, width: 400, height: 3000).transformed(by: .init(translationX: 0, y: 1500)))
            .composited(over: PipelineFixtures.solid(.white, width: 400, height: 6000))
        #expect(AutoCropStep.apply(image).extent == CGRect(x: 0, y: 0, width: 400, height: 4497))
    }

    /// Content 9 to 13 levels off the border is kept on large images, as the full-size rule keeps it.
    @Test(arguments: [245, 242])
    func autoCropKeepsFaintRowOnLargeImages(grey: Int) throws {
        let v = CGFloat(grey) / 255
        let image = CIImage(color: CIColor(red: v, green: v, blue: v, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
            .cropped(to: CGRect(x: 1500, y: 3333, width: 3000, height: 1))
            .composited(over: PipelineFixtures.solid(red, width: 3000, height: 2500).transformed(by: .init(translationX: 1500, y: 500)))
            .composited(over: PipelineFixtures.solid(.white, width: 6000, height: 4000))
        #expect(AutoCropStep.apply(image).extent == CGRect(x: 0, y: 0, width: 3000, height: 2834))
    }

    /// Top-left and bottom-right borders of different colours: the side borders still go on large images.
    @Test func autoCropRemovesSidesWhenCornerColoursDiffer() throws {
        var image = RGBAImage(width: 2400, height: 1600)
        for y in 0..<1600 {
            for x in 0..<2400 {
                let v: UInt8 = y < 200 ? 255 : y >= 1400 ? 0 : x < 200 ? 255 : x >= 2200 ? 0 : 128
                image[x, y] = (v, v, v, 255)
            }
        }
        #expect(AutoCropStep.apply(PipelineFixtures.fromRGBA(image)).extent == CGRect(x: 0, y: 0, width: 2000, height: 1200))
    }

    /// Content only near the top and bottom edges of a large image still bounds the sides.
    @Test func autoCropSeesContentOnlyNearTopAndBottom() throws {
        var pixels = RGBAImage(width: 2000, height: 1500)
        for i in stride(from: 0, to: pixels.pixels.count, by: 4) { pixels.pixels.replaceSubrange(i..<i + 4, with: [255, 255, 255, 255]) }
        for y in 0..<4 { for x in 100..<110 { pixels[x, y + 2] = (0, 0, 0, 255) } }       // near the top
        for y in 0..<4 { for x in 1800..<1810 { pixels[x, 1494 + y] = (0, 0, 0, 255) } }  // near the bottom
        let out = AutoCropStep.apply(PipelineFixtures.fromRGBA(pixels))
        #expect(out.extent == CGRect(x: 0, y: 0, width: 1710, height: 1496))
    }

    @Test func canvasRunsAutoCropFirst() throws {
        var s = perSide(1, 1, 1, 1)
        s.autoCropBorders = true
        let image = framed(width: 40, height: 30, picture: CGRect(x: 5, y: 3, width: 20, height: 20))
        let p = try PipelineFixtures.pixels(CanvasStep.apply(image, s, scale: 1))
        #expect(p.width == 22 && p.height == 22)
        #expect(close(p[0, 0], (0, 0, 0, 255)) && close(p[1, 1], (255, 0, 0, 255)))
    }

    // MARK: Border

    @Test func borderTwoFramesNested() throws {
        var s = BorderSettings()
        s.isOn = true
        s.outerWidth = 2; s.outerColour = .white
        s.innerWidth = 1; s.innerColour = .black
        let p = try PipelineFixtures.pixels(BorderStep.apply(PipelineFixtures.solid(red, width: 4, height: 4), s, scale: 1))
        #expect(p.width == 10 && p.height == 10)
        #expect(close(p[0, 0], (255, 255, 255, 255)) && close(p[1, 1], (255, 255, 255, 255)))
        #expect(close(p[2, 2], (0, 0, 0, 255)) && close(p[7, 7], (0, 0, 0, 255)))
        #expect(close(p[3, 3], (255, 0, 0, 255)) && close(p[6, 6], (255, 0, 0, 255)))
        #expect(close(p[8, 8], (255, 255, 255, 255)) && close(p[9, 9], (255, 255, 255, 255)))
    }

    @Test func borderZeroWidthSkipped() throws {
        var s = BorderSettings()
        s.isOn = true
        s.outerWidth = 0
        s.innerWidth = 2; s.innerColour = .black
        let p = try PipelineFixtures.pixels(BorderStep.apply(PipelineFixtures.solid(red, width: 4, height: 4), s, scale: 1))
        #expect(p.width == 8 && p.height == 8)
        #expect(close(p[0, 0], (0, 0, 0, 255)) && close(p[2, 2], (255, 0, 0, 255)))
        s.innerWidth = 0
        let none = BorderStep.apply(PipelineFixtures.solid(red, width: 4, height: 4), s, scale: 1)
        #expect(none.extent == CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test func offIsIdentity() throws {
        let image = PipelineFixtures.quadrants(width: 6, height: 4)
        var canvas = perSide(5, 5, 5, 5)
        canvas.isOn = false
        canvas.autoCropBorders = true
        var border = BorderSettings()
        border.outerWidth = 3
        let original = try PipelineFixtures.pixels(image)
        #expect(try PipelineFixtures.pixels(CanvasStep.apply(image, canvas, scale: 1)) == original)
        #expect(try PipelineFixtures.pixels(BorderStep.apply(image, border, scale: 1)) == original)
    }

    /// The live preview sizes the output after every keystroke: a huge typed value must not trap on overflow.
    @Test func hugeValuesDoNotOverflow() throws {
        let values = TextValues(name: "a", folder: "f", date: "2026-10-18", index: 1)
        let size = CGSize(width: 100, height: 100)
        var s = BatchSettings()
        s.border.isOn = true
        s.border.outerWidth = 5_000_000_000_000_000_000
        _ = try ImagePipeline.outputSize(for: size, s, values: values)
        s = BatchSettings()
        s.canvas = perSide(.max / 2, .max / 2, .max, 0)
        _ = try ImagePipeline.outputSize(for: size, s, values: values)
        s.canvas = totalSize(.max, .max, .center)
        _ = try ImagePipeline.outputSize(for: size, s, values: values)
        s.canvas.method = .aspectRatio
        s.canvas.ratioWidth = 1e17
        _ = try ImagePipeline.outputSize(for: size, s, values: values)
        s.canvas.ratioWidth = 1
        s.canvas.ratioHeight = 1e17
        _ = try ImagePipeline.outputSize(for: size, s, values: values)
    }
}
