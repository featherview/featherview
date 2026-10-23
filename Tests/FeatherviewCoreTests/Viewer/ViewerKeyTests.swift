import Testing
@testable import FeatherviewCore

@Suite struct ViewerKeyTests {
    // Caps Lock gives uppercase without Shift; US '+' is Shift+=; AZERTY digits need Shift.
    @Test(arguments: [
        ("r", false, ViewerKey.rotateRight), ("R", false, .rotateRight), ("l", false, .rotateLeft), ("L", false, .rotateLeft),
        ("=", false, .zoomIn), ("+", true, .zoomIn), ("0", true, .fit), ("1", true, .actualSize), ("-", true, .zoomOut),
        ("2", false, .zoomToWidth), ("2", true, .zoomToWidth), ("3", false, .zoomToHeight),
        ("o", false, .open), ("b", false, .batch), ("m", false, .minimize), ("p", false, .settings),
        ("s", false, .saveAs), ("a", false, .about), ("A", true, .playInWindow),
        ("g", false, .toggleAnimation), ("G", false, .toggleAnimation),
        ("h", false, .flipHorizontal), ("v", false, .flipVertical), ("L", true, .toggleKeepZoom),
        ("x", false, .swapImages), ("d", false, .toggleDifference), ("D", false, .toggleDifference),
        ("t", false, .toggleThumbnails), ("T", false, .toggleThumbnails), ("w", false, .slideshow), ("W", false, .slideshow),
    ] as [(String, Bool, ViewerKey)])
    func viewerKeys(_ characters: String, _ shift: Bool, _ action: ViewerKey) {
        #expect(ViewerKey.action(characters: characters, shift: shift) == action)
    }

    @Test(arguments: [
        ("q", false), ("R", true), ("S", true), ("G", true), ("H", true), ("X", true), ("D", true), ("T", true), ("W", true),
    ] as [(String, Bool)])
    func keysWithoutAnAction(_ characters: String, _ shift: Bool) {
        #expect(ViewerKey.action(characters: characters, shift: shift) == nil)
    }

    @Test func arrowStepsFollowLayoutDirection() {
        #expect(ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: false))
        #expect(!ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: false))
        #expect(!ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: true))   // → is previous in Arabic/Hebrew
        #expect(ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: true))
    }
}
