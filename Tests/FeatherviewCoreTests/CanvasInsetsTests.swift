import CoreGraphics
import FeatherviewCore
import Testing

struct CanvasInsetsTests {
    @Test func windowedWithStrip() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(insets.top == 52)
        #expect(insets.bottom == 38)
    }

    @Test func hiddenStatusBarFreesTheBottom() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: false, fullScreen: false)
        #expect(insets.top == 52)
        #expect(insets.bottom == 0)
    }

    @Test func fullScreenUsesTheWholeScreen() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: true)
        #expect(insets.top == 0)
        #expect(insets.bottom == 0)
    }

    @Test func fitAreaSubtracts() {
        let insets = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(insets.fitArea(in: CGSize(width: 960, height: 640)) == CGSize(width: 960, height: 550))
    }

    /// The bars fade but stay laid out, so `make` has no auto-hide input: the same inputs, the same insets.
    @Test func insetsDontChangeWhenBarsAutoHide() {
        let shown = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        let faded = CanvasInsets.make(toolbarHeight: 52, statusBarShown: true, fullScreen: false)
        #expect(shown == faded)
    }
}
