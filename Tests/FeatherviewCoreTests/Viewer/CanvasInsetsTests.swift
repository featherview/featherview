import CoreGraphics
import FeatherviewCore
import Testing

struct CanvasInsetsTests {
    /// docs/DESIGN.md "Window layout": 16 / 60 / 16 / 44 under a 52 pt title bar with the strip.
    @Test func windowedWithStrip() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(insets.top == 60)
        #expect(insets.bottom == 44)
        #expect(insets.leading == 16)
        #expect(insets.trailing == 16)
    }

    @Test func hiddenStatusBarFreesTheBottom() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: false, fullScreen: false)
        #expect(insets.top == 60)
        #expect(insets.bottom == 16)
    }

    @Test func fullScreenUsesTheWholeScreen() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: true)
        #expect(insets == CanvasInsets(top: 0, bottom: 0, leading: 0, trailing: 0))
    }

    @Test func fitAreaSubtracts() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(insets.fitArea(in: CGSize(width: 1220, height: 700)) == CGSize(width: 1188, height: 596))
    }

    /// The on-image error box sits above the glass strip, not on it, and keeps the side margin without one.
    @Test func messageBoxClearsTheStrip() {
        let shown = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(shown.messageBottom >= CanvasInsets.stripHeight + CanvasInsets.stripMargin + CanvasInsets.clearance)
        let hidden = CanvasInsets.make(toolbarHeight: 52, statusBarShown: false, fullScreen: false)
        #expect(hidden.messageBottom == CanvasInsets.side)
    }

    /// docs/DESIGN.md: with the info panel open the trailing inset is 12 + 280 + 16 = 308.
    @Test func infoPanelTakesTheTrailingSide() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false, infoPanelShown: true)
        #expect(insets.trailing == 308)
        #expect(insets.leading == 16)
        #expect(insets.fitArea(in: CGSize(width: 1220, height: 700)).width == 896)
    }

    /// In full screen the picture fills the screen, but never runs under an open panel.
    @Test func infoPanelInFullScreen() {
        let insets = CanvasInsets.make(toolbarHeight: 0, statusBarShown: false, fullScreen: true, infoPanelShown: true)
        #expect(insets.trailing == 308)
        #expect(insets.leading == 0)
    }
}
