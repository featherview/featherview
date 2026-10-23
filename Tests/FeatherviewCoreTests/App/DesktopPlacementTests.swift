import Testing
@testable import FeatherviewCore

@Suite struct DesktopPlacementTests {
    /// `NSImageScaling` raw values: 3 proportionallyUpOrDown, 1 axesIndependently, 2 none.
    @Test func placementsMapToWorkspaceOptions() {
        #expect(DesktopPlacement.fill.scalingRawValue == 3 && DesktopPlacement.fill.allowsClipping)
        #expect(DesktopPlacement.fit.scalingRawValue == 3 && !DesktopPlacement.fit.allowsClipping)
        #expect(DesktopPlacement.stretch.scalingRawValue == 1 && !DesktopPlacement.stretch.allowsClipping)
        #expect(DesktopPlacement.center.scalingRawValue == 2 && !DesktopPlacement.center.allowsClipping)
        #expect(DesktopPlacement.allCases.count == 4)
    }
}
