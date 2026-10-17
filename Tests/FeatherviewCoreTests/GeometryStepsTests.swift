import CoreImage
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct GeometryStepsTests {
    private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    private static let red = (255, 0, 0, 255), green = (0, 255, 0, 255)
    private static let blue = (0, 0, 255, 255), white = (255, 255, 255, 255)

    private func close(_ a: Pixel, _ b: (Int, Int, Int, Int)) -> Bool {
        abs(Int(a.r) - b.0) <= 1 && abs(Int(a.g) - b.1) <= 1 && abs(Int(a.b) - b.2) <= 1 && abs(Int(a.a) - b.3) <= 1
    }

    /// Each pixel names its own place: red = x × 20, green = y × 20 (y = 0 is the top row).
    private func coordinates(width: Int, height: Int) -> CIImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height { for x in 0..<width { image[x, y] = (UInt8(x * 20), UInt8(y * 20), 0, 255) } }
        return PipelineFixtures.fromRGBA(image)
    }

    /// The picture position the result's top-left pixel came from.
    private func origin(_ image: RGBAImage) -> (x: Int, y: Int) {
        let p = image[0, 0]
        return ((Int(p.r) + 10) / 20, (Int(p.g) + 10) / 20)
    }

    private func crop(x: Int, y: Int, width: Int, height: Int, _ anchor: ImageAnchor) -> CropSettings {
        var s = CropSettings()
        s.isOn = true; s.x = x; s.y = y; s.width = width; s.height = height; s.anchor = anchor
        return s
    }

    // MARK: Crop

    // A coordinate image instead of quadrants: quadrant colours can't tell `top` from `topLeft`.
    @Test(arguments: [
        (ImageAnchor.topLeft, 1, 1), (.top, 4, 1), (.topRight, 5, 1),
        (.left, 1, 3), (.center, 4, 3), (.right, 5, 3),
        (.bottomLeft, 1, 3), (.bottom, 4, 3), (.bottomRight, 5, 3),
    ])
    func cropFromEachAnchor(anchor: ImageAnchor, x: Int, y: Int) throws {
        let out = CropStep.apply(coordinates(width: 10, height: 8), crop(x: 1, y: 1, width: 4, height: 4, anchor), scale: 1)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 4, height: 4))
        let o = origin(try PipelineFixtures.pixels(out))
        #expect(o.x == x && o.y == y)
    }

    @Test func zeroWidthCropsToTheEdge() throws {
        let image = coordinates(width: 10, height: 8)
        let fromTopLeft = CropStep.apply(image, crop(x: 3, y: 2, width: 0, height: 0, .topLeft), scale: 1)
        #expect(fromTopLeft.extent.size == CGSize(width: 7, height: 6))
        let o1 = origin(try PipelineFixtures.pixels(fromTopLeft))
        #expect(o1.x == 3 && o1.y == 2)
        let fromBottomRight = CropStep.apply(image, crop(x: 3, y: 2, width: 0, height: 0, .bottomRight), scale: 1)
        #expect(fromBottomRight.extent.size == CGSize(width: 7, height: 6))
        let o2 = origin(try PipelineFixtures.pixels(fromBottomRight))
        #expect(o2.x == 0 && o2.y == 0)
    }

    @Test func cropIsClippedToThePicture() throws {
        let out = CropStep.apply(coordinates(width: 10, height: 8), crop(x: 8, y: 6, width: 5, height: 5, .topLeft), scale: 1)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 2, height: 2))
        let o = origin(try PipelineFixtures.pixels(out))
        #expect(o.x == 8 && o.y == 6)
    }

    @Test func cropOutsideImageKeepsImage() {
        let out = CropStep.apply(coordinates(width: 10, height: 8), crop(x: 20, y: 1, width: 4, height: 4, .topLeft), scale: 1)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 10, height: 8))
    }

    @Test func cropScalesWithPreview() throws {
        let out = CropStep.apply(coordinates(width: 10, height: 8), crop(x: 2, y: 2, width: 4, height: 4, .topLeft), scale: 0.5)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 2, height: 2))
        let o = origin(try PipelineFixtures.pixels(out))
        #expect(o.x == 1 && o.y == 1)
    }

    @Test func cropOffIsIdentity() {
        let image = coordinates(width: 10, height: 8)
        var s = crop(x: 1, y: 1, width: 4, height: 4, .topLeft)
        s.isOn = false
        #expect(CropStep.apply(image, s, scale: 1).extent == image.extent)
    }

    // MARK: Resize

    struct SizeCase: Sendable, CustomTestStringConvertible {
        var mode: ResizeMode
        var width: Int? = nil, height: Int? = nil, side = 1920, megapixels = 12.0
        var percentWidth = 50.0, percentHeight = 50.0
        var keepAspect = true, dontEnlarge = true, dontShrink = false
        var input: CGSize
        var expected: CGSize
        var testDescription: String { "\(mode) \(Int(input.width))×\(Int(input.height)) → \(Int(expected.width))×\(Int(expected.height))" }

        var settings: ResizeSettings {
            var s = ResizeSettings()
            s.isOn = true; s.mode = mode; s.width = width; s.height = height; s.side = side; s.megapixels = megapixels
            s.percentWidth = percentWidth; s.percentHeight = percentHeight
            s.keepAspect = keepAspect; s.dontEnlarge = dontEnlarge; s.dontShrink = dontShrink
            return s
        }
    }

    private static let landscape = CGSize(width: 4000, height: 3000), portrait = CGSize(width: 3000, height: 4000)
    private static func size(_ w: Int, _ h: Int) -> CGSize { CGSize(width: w, height: h) }

    @Test(arguments: [
        // width and/or height
        SizeCase(mode: .widthHeight, width: 2000, input: landscape, expected: size(2000, 1500)),
        SizeCase(mode: .widthHeight, width: 2000, input: portrait, expected: size(2000, 2667)),
        SizeCase(mode: .widthHeight, width: 2000, keepAspect: false, input: landscape, expected: size(2000, 3000)),
        SizeCase(mode: .widthHeight, height: 1000, input: landscape, expected: size(1333, 1000)),
        SizeCase(mode: .widthHeight, height: 1000, input: portrait, expected: size(750, 1000)),
        SizeCase(mode: .widthHeight, height: 1000, keepAspect: false, input: portrait, expected: size(3000, 1000)),
        SizeCase(mode: .widthHeight, width: 1000, height: 1000, input: landscape, expected: size(1000, 750)),
        SizeCase(mode: .widthHeight, width: 1000, height: 1000, input: portrait, expected: size(750, 1000)),
        SizeCase(mode: .widthHeight, width: 1000, height: 1000, keepAspect: false, input: landscape, expected: size(1000, 1000)),
        SizeCase(mode: .widthHeight, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .widthHeight, width: 8000, height: 8000, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .widthHeight, width: 8000, height: 8000, dontEnlarge: false, input: landscape, expected: size(8000, 6000)),
        SizeCase(mode: .widthHeight, width: 5000, height: 1000, keepAspect: false, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .widthHeight, width: 5000, height: 1000, keepAspect: false, dontEnlarge: false,
                 input: landscape, expected: size(5000, 1000)),
        SizeCase(mode: .widthHeight, width: 5000, height: 1000, keepAspect: false, dontEnlarge: false, dontShrink: true,
                 input: landscape, expected: size(4000, 3000)),
        // longest / shortest side
        SizeCase(mode: .longestSide, input: landscape, expected: size(1920, 1440)),
        SizeCase(mode: .longestSide, input: portrait, expected: size(1440, 1920)),
        SizeCase(mode: .longestSide, side: 8000, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .longestSide, side: 8000, dontEnlarge: false, input: portrait, expected: size(6000, 8000)),
        SizeCase(mode: .longestSide, dontShrink: true, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .longestSide, side: 8000, dontEnlarge: false, dontShrink: true, input: landscape, expected: size(8000, 6000)),
        SizeCase(mode: .shortestSide, side: 1000, input: landscape, expected: size(1333, 1000)),
        SizeCase(mode: .shortestSide, side: 1000, input: portrait, expected: size(1000, 1333)),
        // megapixels
        SizeCase(mode: .megapixels, megapixels: 3, input: landscape, expected: size(2000, 1500)),
        SizeCase(mode: .megapixels, megapixels: 3, input: portrait, expected: size(1500, 2000)),
        SizeCase(mode: .megapixels, megapixels: 48, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .megapixels, megapixels: 48, dontEnlarge: false, input: landscape, expected: size(8000, 6000)),
        // percent
        SizeCase(mode: .percent, percentWidth: 25, input: landscape, expected: size(1000, 750)),
        SizeCase(mode: .percent, percentWidth: 25, input: portrait, expected: size(750, 1000)),
        SizeCase(mode: .percent, percentWidth: 25, keepAspect: false, input: landscape, expected: size(1000, 1500)),
        SizeCase(mode: .percent, percentWidth: 200, input: landscape, expected: size(4000, 3000)),
        SizeCase(mode: .percent, percentWidth: 200, dontEnlarge: false, input: landscape, expected: size(8000, 6000)),
        SizeCase(mode: .percent, percentWidth: 25, dontShrink: true, input: landscape, expected: size(4000, 3000)),
    ])
    func targetSizeTable(_ c: SizeCase) {
        #expect(ResizeStep.targetSize(for: c.input, c.settings, scale: 1) == c.expected)
    }

    @Test func resizeNeverBelowOnePixel() {
        let s = SizeCase(mode: .percent, percentWidth: 1, input: Self.size(10, 10), expected: Self.size(1, 1))
        #expect(ResizeStep.targetSize(for: s.input, s.settings, scale: 1) == s.expected)
        let zero = SizeCase(mode: .percent, percentWidth: 0, input: Self.size(10, 10), expected: Self.size(1, 1))
        #expect(ResizeStep.targetSize(for: zero.input, zero.settings, scale: 1) == zero.expected)
        let out = ResizeStep.apply(PipelineFixtures.solid(.white, width: 10, height: 10), s.settings, scale: 1)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func percentIgnoresScale() {
        let percent = SizeCase(mode: .percent, input: Self.landscape, expected: Self.size(2000, 1500))
        #expect(ResizeStep.targetSize(for: Self.landscape, percent.settings, scale: 0.5) == Self.size(2000, 1500))
        // Pixel values do follow the preview's scale; megapixels by its square.
        let side = SizeCase(mode: .longestSide, input: Self.landscape, expected: .zero)
        #expect(ResizeStep.targetSize(for: Self.size(2000, 1500), side.settings, scale: 0.5) == Self.size(960, 720))
        let mp = SizeCase(mode: .megapixels, megapixels: 3, input: Self.landscape, expected: .zero)
        #expect(ResizeStep.targetSize(for: Self.size(2000, 1500), mp.settings, scale: 0.5) == Self.size(1000, 750))
    }

    @Test func applyGivesExactTargetSize() throws {
        let s = SizeCase(mode: .longestSide, side: 1000, input: Self.size(3000, 2000), expected: Self.size(1000, 667))
        let out = ResizeStep.apply(PipelineFixtures.solid(.white, width: 3000, height: 2000), s.settings, scale: 1)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 1000, height: 667))
        // Edges stay opaque: the resample doesn't pull in transparency from outside the picture.
        let pixels = try PipelineFixtures.pixels(out)
        #expect(close(pixels[0, 0], Self.white) && close(pixels[999, 666], Self.white))
    }

    @Test func resizeOffIsIdentity() {
        var s = ResizeSettings()
        s.side = 10
        #expect(ResizeStep.apply(PipelineFixtures.solid(.white, width: 30, height: 20), s, scale: 1).extent.size
            == CGSize(width: 30, height: 20))
    }

    @Test func decodeLimitOnlyForPlainDownscale() {
        var settings = BatchSettings()
        settings.resize.isOn = true
        settings.resize.mode = .longestSide
        settings.resize.side = 1920
        #expect(ResizeStep.decodeLimit(settings, originalSize: Self.landscape) == 1920)
        // A smaller image isn't enlarged: it needs its full size.
        #expect(ResizeStep.decodeLimit(settings, originalSize: Self.size(800, 600)) == nil)
        var cropped = settings
        cropped.crop.isOn = true
        #expect(ResizeStep.decodeLimit(cropped, originalSize: Self.landscape) == nil)
        var percent = settings
        percent.resize.mode = .percent
        #expect(ResizeStep.decodeLimit(percent, originalSize: Self.landscape) == nil)
        var off = settings
        off.resize.isOn = false
        #expect(ResizeStep.decodeLimit(off, originalSize: Self.landscape) == nil)
    }

    // MARK: Orientation

    private func orient(_ rotate: QuarterTurn, h: Bool = false, v: Bool = false) throws -> RGBAImage {
        var s = OrientationSettings()
        s.rotate = rotate; s.flipHorizontal = h; s.flipVertical = v
        let out = OrientationStep.apply(PipelineFixtures.quadrants(width: 6, height: 4), s)
        #expect(out.extent.origin == .zero)
        return try PipelineFixtures.pixels(out)
    }

    @Test func rotateLeftMovesTopLeftToBottomLeft() throws {
        let p = try orient(.left)
        #expect(p.width == 4 && p.height == 6)
        #expect(close(p[0, 5], Self.red) && close(p[0, 0], Self.green) && close(p[3, 0], Self.white) && close(p[3, 5], Self.blue))
    }

    @Test func rotateRightMovesTopLeftToTopRight() throws {
        let p = try orient(.right)
        #expect(p.width == 4 && p.height == 6)
        #expect(close(p[3, 0], Self.red) && close(p[0, 0], Self.blue) && close(p[0, 5], Self.white) && close(p[3, 5], Self.green))
    }

    @Test func flipsMirrorTheRightAxis() throws {
        let h = try orient(.none, h: true)
        #expect(h.width == 6 && h.height == 4)
        #expect(close(h[0, 0], Self.green) && close(h[5, 0], Self.red) && close(h[0, 3], Self.white))
        let v = try orient(.none, v: true)
        #expect(close(v[0, 0], Self.blue) && close(v[5, 0], Self.white) && close(v[0, 3], Self.red))
    }

    @Test func rotateThenFlipOrder() throws {
        // Right turn first (top-left blue, top-right red), then the horizontal flip.
        let p = try orient(.right, h: true)
        #expect(close(p[0, 0], Self.red) && close(p[3, 0], Self.blue) && close(p[0, 5], Self.green) && close(p[3, 5], Self.white))
    }

    @Test func offIsIdentity() {
        let image = PipelineFixtures.quadrants(width: 6, height: 4)
        #expect(OrientationStep.apply(image, OrientationSettings()).extent == image.extent)
    }
}
