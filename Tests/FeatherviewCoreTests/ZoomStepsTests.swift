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

    @Test func stepsStayInRange() {
        #expect(ZoomSteps.step(16, by: 1.1) == 16)
        #expect(ZoomSteps.step(0.05, by: 1 / 1.1) == 0.05)
    }
}
