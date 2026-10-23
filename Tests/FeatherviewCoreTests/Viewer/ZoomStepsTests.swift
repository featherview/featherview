import CoreGraphics
import Testing
@testable import FeatherviewCore

@Suite struct ZoomStepsTests {
    @Test func fitFactorIsTheScaleOnScreen() {
        #expect(ZoomSteps.fitFactor(image: CGSize(width: 6000, height: 4000),
                                    view: CGSize(width: 1200, height: 900), displayScale: 1) == 0.2)
        #expect(ZoomSteps.fitFactor(image: CGSize(width: 4000, height: 3000),
                                    view: CGSize(width: 1000, height: 1000), displayScale: 2) == 0.5)
    }

    @Test func clampedKeepsTheRange() {
        #expect(ZoomSteps.clamped(0.01) == 0.05 && ZoomSteps.clamped(20) == 16 && ZoomSteps.clamped(1.5) == 1.5)
    }

    @Test func percentRoundsToWhole() {
        #expect(ZoomSteps.percent(0.333) == 33 && ZoomSteps.percent(0.335) == 34 && ZoomSteps.percent(2) == 200)
    }

    @Test func fitNeverEnlarges() {
        #expect(ZoomSteps.fitFactor(image: CGSize(width: 100, height: 100),
                                    view: CGSize(width: 1000, height: 1000), displayScale: 2) == 1)
    }

    @Test func zoomOutFromFitShrinks() {
        let fit = ZoomSteps.fitFactor(image: CGSize(width: 6000, height: 4000),
                                      view: CGSize(width: 1200, height: 900), displayScale: 1)
        #expect(abs(ZoomSteps.step(fit, by: 1 / 1.1) - 0.2 / 1.1) < 1e-9)
        #expect(abs(ZoomSteps.step(fit, by: 1.1) - 0.22) < 1e-9)
    }

    @Test func pixelsShowFromTwiceTheirSizeOnScreen() {
        // 1000 px drawn 1000 pt wide on Retina is 200 %: pixels show.
        #expect(ZoomSteps.showsPixels(drawnWidth: 1000, imageWidth: 1000, displayScale: 2))
        #expect(!ZoomSteps.showsPixels(drawnWidth: 999, imageWidth: 1000, displayScale: 2))
        #expect(ZoomSteps.showsPixels(drawnWidth: 2000, imageWidth: 1000, displayScale: 1))
        #expect(!ZoomSteps.showsPixels(drawnWidth: 1500, imageWidth: 1000, displayScale: 1))
    }

    private func near(_ a: CGSize, _ b: CGSize) -> Bool { abs(a.width - b.width) < 1e-6 && abs(a.height - b.height) < 1e-6 }

    @Test func zoomDrawSizeUsesFullPixels() {
        let size = ZoomSteps.drawSize(decoded: CGSize(width: 4344, height: 2896), full: CGSize(width: 8688, height: 5792),
                                      factor: 0.44, view: CGSize(width: 1500, height: 900), displayScale: 2)
        #expect(near(size, CGSize(width: 1911.36, height: 1274.24)))
    }

    @Test func zoomDrawSizeWithoutFullUsesDecoded() {
        let size = ZoomSteps.drawSize(decoded: CGSize(width: 4344, height: 2896), full: nil,
                                      factor: 0.44, view: CGSize(width: 1500, height: 900), displayScale: 2)
        #expect(near(size, CGSize(width: 955.68, height: 637.12)))
    }

    @Test func fitDrawSizeNeverEnlargesAndShrinksToTheView() {
        // Small image: never enlarged.
        #expect(ZoomSteps.drawSize(decoded: CGSize(width: 400, height: 300), full: CGSize(width: 400, height: 300),
                                   factor: nil, view: CGSize(width: 1500, height: 900), displayScale: 2)
                == CGSize(width: 200, height: 150))
        // Large image: shrunk to the view, from the decoded pixels, rounded.
        #expect(ZoomSteps.drawSize(decoded: CGSize(width: 4344, height: 2896), full: CGSize(width: 8688, height: 5792),
                                   factor: nil, view: CGSize(width: 1500, height: 900), displayScale: 2)
                == CGSize(width: 1350, height: 900))
    }

    @Test func placeholderSmoothsAtActualSizeOfTheFullFile() {
        // Half-size fit decode of an 8688 px file at 100 %: drawn 4344 pt on Retina is 1×, so smoothed.
        let pixels = ZoomSteps.pixelSize(decoded: CGSize(width: 4344, height: 2896), full: CGSize(width: 8688, height: 5792))
        #expect(pixels == CGSize(width: 8688, height: 5792))
        #expect(!ZoomSteps.showsPixels(drawnWidth: 4344, imageWidth: Int(pixels.width), displayScale: 2))
    }

    @Test func staleFullSizeFromBeforeARotationIsIgnored() {
        // The file info read before R still says landscape; the rotated decode is portrait.
        #expect(ZoomSteps.pixelSize(decoded: CGSize(width: 2896, height: 4344), full: CGSize(width: 4344, height: 2896))
                == CGSize(width: 2896, height: 4344))
        #expect(ZoomSteps.drawSize(decoded: CGSize(width: 2896, height: 4344), full: CGSize(width: 4344, height: 2896),
                                   factor: 1, view: CGSize(width: 1500, height: 900), displayScale: 2)
                == CGSize(width: 1448, height: 2172))
        // A decode step rounds each side; that still counts as the same file.
        #expect(ZoomSteps.pixelSize(decoded: CGSize(width: 543, height: 362), full: CGSize(width: 4345, height: 2897))
                == CGSize(width: 4345, height: 2897))
    }

    private let view = CGSize(width: 1400, height: 800)

    @Test func fillWidthEnlarges() {
        let factor = ZoomSteps.fillFactor(image: CGSize(width: 900, height: 3000), view: view, displayScale: 2, mode: .width)
        #expect(abs(factor - 2800.0 / 900) < 1e-9)
    }

    @Test func fillHeightShrinks() {
        let factor = ZoomSteps.fillFactor(image: CGSize(width: 4000, height: 700), view: CGSize(width: 1400, height: 300),
                                          displayScale: 2, mode: .height)
        #expect(abs(factor - 600.0 / 700) < 1e-9)
    }

    @Test func fillFactorClamps() {
        #expect(ZoomSteps.fillFactor(image: CGSize(width: 10, height: 20_000), view: view, displayScale: 2, mode: .width) == 16)
        #expect(ZoomSteps.fillFactor(image: CGSize(width: 100_000, height: 10), view: view, displayScale: 2, mode: .width) == 0.05)
        #expect(ZoomSteps.fillFactor(image: CGSize(width: 1, height: 1), view: view, displayScale: 2, mode: .height) == 16)
        #expect(ZoomSteps.fillFactor(image: .zero, view: view, displayScale: 2, mode: .width) == 1)
    }

    @Test func fitModeFitIsFitFactor() {
        let image = CGSize(width: 8688, height: 5792)
        #expect(ZoomSteps.fillFactor(image: image, view: view, displayScale: 2, mode: .fit)
                == ZoomSteps.fitFactor(image: image, view: view, displayScale: 2))
    }

    @Test func startOriginTop() {
        let clear = CGSize(width: 2800, height: 1600)
        #expect(ZoomSteps.startOrigin(.top, document: CGSize(width: 2800, height: 9000), clear: clear, rightToLeft: false)
                == CGPoint(x: 0, y: 0))
        #expect(ZoomSteps.startOrigin(.top, document: CGSize(width: 1000, height: 9000), clear: clear, rightToLeft: false)
                == CGPoint(x: -900, y: 0))
    }

    @Test func startOriginLeading() {
        #expect(ZoomSteps.startOrigin(.leading, document: CGSize(width: 9000, height: 1600),
                                      clear: CGSize(width: 2800, height: 1600), rightToLeft: false) == CGPoint(x: 0, y: 0))
    }

    @Test func leadingStartIsRightInRightToLeft() {
        #expect(ZoomSteps.startOrigin(.leading, document: CGSize(width: 9000, height: 1600),
                                      clear: CGSize(width: 2800, height: 1600), rightToLeft: true) == CGPoint(x: 6200, y: 0))
    }

    @Test func keepHasNoOrigin() {
        #expect(ZoomSteps.startOrigin(.keep, document: CGSize(width: 9000, height: 1600),
                                      clear: CGSize(width: 2800, height: 1600), rightToLeft: false) == nil)
    }
}
