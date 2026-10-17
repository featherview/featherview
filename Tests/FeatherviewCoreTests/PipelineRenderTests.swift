import CoreImage
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PipelineRenderTests {
    private func close(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (Int, Int, Int, Int)) -> Bool {
        abs(Int(a.r) - b.0) <= 1 && abs(Int(a.g) - b.1) <= 1 && abs(Int(a.b) - b.2) <= 1 && abs(Int(a.a) - b.3) <= 1
    }

    @Test func solidRendersItsColour() throws {
        let colour = RGBAColor(red: 0.2, green: 0.4, blue: 0.6)
        let image = try PipelineFixtures.pixels(PipelineFixtures.solid(colour, width: 5, height: 3))
        #expect(image.width == 5 && image.height == 3)
        #expect(close(image[2, 1], (51, 102, 153, 255)))
    }

    @Test func quadrantsAreTopFirst() throws {
        let image = try PipelineFixtures.pixels(PipelineFixtures.quadrants(width: 4, height: 4))
        #expect(close(image[0, 0], (255, 0, 0, 255)))
        #expect(close(image[3, 0], (0, 255, 0, 255)))
        #expect(close(image[0, 3], (0, 0, 255, 255)))
        #expect(close(image[3, 3], (255, 255, 255, 255)))
    }

    @Test func halfTransparentStaysStraightAlpha() throws {
        let image = try PipelineFixtures.pixels(
            PipelineFixtures.solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 2, height: 2))
        #expect(close(image[1, 1], (255, 0, 0, 128)))
        // The CGImage itself is straight, so the raw-pixel step after the render reads true colours.
        let cg = try PipelineRender.cgImage(PipelineFixtures.solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5),
                                                                    width: 2, height: 2))
        #expect(cg.alphaInfo == .last)
    }

    @Test func halfTransparentStaysStraightAfterAFilter() throws {
        let red = PipelineFixtures.solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 2, height: 2)
        let image = try PipelineFixtures.pixels(red.applyingFilter("CIColorClamp"))
        #expect(close(image[1, 1], (255, 0, 0, 128)))
    }

    /// Faint pixels (a soft shadow edge) keep their straight colour exactly when nothing filters them,
    /// and within 1 after a filter: no 8-bit premultiplied round trip.
    @Test func faintPixelsKeepTheirColour() throws {
        var source = RGBAImage(width: 2, height: 1)
        source[0, 0] = (200, 100, 50, 4)
        source[1, 0] = (17, 230, 99, 1)
        let plain = PipelineFixtures.fromRGBA(source)
        for (image, tolerance) in [(plain, 0), (plain.applyingFilter("CIColorClamp"), 1)] {
            let cg = try PipelineRender.cgImage(image)
            let bytes = [UInt8](cg.dataProvider!.data! as Data)
            for (n, i) in [0, 4].enumerated() {
                let want = source[n, 0]
                #expect(abs(Int(bytes[i]) - Int(want.r)) <= tolerance && abs(Int(bytes[i + 1]) - Int(want.g)) <= tolerance
                    && abs(Int(bytes[i + 2]) - Int(want.b)) <= tolerance && bytes[i + 3] == want.a,
                    "\(bytes[i..<i + 4]) vs \(want)")
            }
        }
    }

    @Test func movedExtentRendersFromOrigin() throws {
        let moved = PipelineFixtures.quadrants(width: 4, height: 4).transformed(by: .init(translationX: 10, y: -7))
        let image = try PipelineFixtures.pixels(moved)
        #expect(image.width == 4 && image.height == 4)
        #expect(close(image[0, 0], (255, 0, 0, 255)))
    }

    @Test func infiniteExtentThrows() {
        #expect(throws: EncodeError.failed) { try PipelineRender.cgImage(CIImage(color: .red)) }
        #expect(throws: EncodeError.failed) { try PipelineRender.cgImage(CIImage.empty()) }
    }
}
