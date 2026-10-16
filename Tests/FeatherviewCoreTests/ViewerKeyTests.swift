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

    @Test func shiftedLettersAreNotShortcuts() {
        #expect(ViewerKey.action(characters: "R", shift: true) == nil)
    }
}
