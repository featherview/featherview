import Testing
@testable import FeatherviewCore

@Suite struct ViewerKeyTests {
    @Test func mapsCharacters() {
        #expect(ViewerKey.action(characters: "r", shift: false) == .rotateRight)
        #expect(ViewerKey.action(characters: "R", shift: false) == .rotateRight)  // Caps Lock
        #expect(ViewerKey.action(characters: "=", shift: false) == .zoomIn)
        #expect(ViewerKey.action(characters: "x", shift: false) == nil)
    }

    // US '+' is Shift+=; AZERTY digits need Shift.
    @Test(arguments: [("+", ViewerKey.zoomIn), ("0", .fit), ("1", .actualSize), ("-", .zoomOut)])
    func shiftTypedCharactersWork(_ characters: String, _ action: ViewerKey) {
        #expect(ViewerKey.action(characters: characters, shift: true) == action)
    }

    @Test(arguments: [("o", ViewerKey.open), ("b", .batch), ("m", .minimize), ("p", .settings)])
    func commandsHaveSingleKeysLikeTheReferenceViewer(_ characters: String, _ action: ViewerKey) {
        #expect(ViewerKey.action(characters: characters, shift: false) == action)
    }

    @Test func shiftedLettersAreNotShortcuts() {
        #expect(ViewerKey.action(characters: "R", shift: true) == nil)
    }

    @Test func saveAsAndAbout() {
        #expect(ViewerKey.action(characters: "s", shift: false) == .saveAs)
        #expect(ViewerKey.action(characters: "a", shift: false) == .about)
        #expect(ViewerKey.action(characters: "S", shift: true) == nil)
    }

    @Test func gTogglesAnimation() {
        #expect(ViewerKey.action(characters: "g", shift: false) == .toggleAnimation)
        #expect(ViewerKey.action(characters: "G", shift: false) == .toggleAnimation)  // Caps Lock
        #expect(ViewerKey.action(characters: "G", shift: true) == nil)
    }

    @Test func flipKeys() {
        #expect(ViewerKey.action(characters: "h", shift: false) == .flipHorizontal)
        #expect(ViewerKey.action(characters: "v", shift: false) == .flipVertical)
        #expect(ViewerKey.action(characters: "H", shift: true) == nil)
    }

    @Test func fillKeys() {
        #expect(ViewerKey.action(characters: "2", shift: false) == .zoomToWidth)
        #expect(ViewerKey.action(characters: "3", shift: false) == .zoomToHeight)
        #expect(ViewerKey.action(characters: "2", shift: true) == .zoomToWidth)  // AZERTY
    }

    @Test func shiftLTogglesKeepZoom() {
        #expect(ViewerKey.action(characters: "L", shift: true) == .toggleKeepZoom)
        #expect(ViewerKey.action(characters: "l", shift: false) == .rotateLeft)
        #expect(ViewerKey.action(characters: "L", shift: false) == .rotateLeft)  // Caps Lock
        #expect(ViewerKey.action(characters: "R", shift: true) == nil)
    }

    @Test func arrowStepsFollowLayoutDirection() {
        #expect(ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: false))
        #expect(!ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: false))
        #expect(!ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: true))   // → is previous in Arabic/Hebrew
        #expect(ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: true))
    }

    @Test func tTogglesThumbnails() {
        #expect(ViewerKey.action(characters: "t", shift: false) == .toggleThumbnails)
        #expect(ViewerKey.action(characters: "T", shift: false) == .toggleThumbnails)  // Caps Lock
        #expect(ViewerKey.action(characters: "T", shift: true) == nil)
    }
}
