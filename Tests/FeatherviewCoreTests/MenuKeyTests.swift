import Testing
@testable import FeatherviewCore

@Suite struct MenuKeyTests {
    @Test func letterMovesFromTitleToKey() {
        let key = MenuKey.parse("Open…  (O)")
        #expect(key == MenuKey(title: "Open…", key: "o", modifiers: []))
    }

    // The column shows one key: the first one without modifiers.
    @Test func prefersAPlainKey() {
        #expect(MenuKey.parse("Next  (→ or Space)")?.key == "\u{F703}")
        #expect(MenuKey.parse("Move to Trash  (⌘⌫ or ⌦)")?.key == "\u{F728}")
        #expect(MenuKey.parse("Previous  (← or ⌫)")?.key == "\u{F702}")
    }

    @Test func keepsModifiersWhenThereIsNoPlainKey() {
        #expect(MenuKey.parse("Next Page  (⌥→)") == MenuKey(title: "Next Page", key: "\u{F703}", modifiers: [.option]))
    }

    @Test(arguments: [("F7", "\u{F70A}"), ("F8", "\u{F70B}"), ("Space", " "), ("⌫", "\u{8}"), ("−", "-"), ("+", "+"), ("0", "0")])
    func namedKeys(_ name: String, _ key: String) {
        #expect(MenuKey.parse("X  (\(name))")?.key == key)
    }

    @Test func titlesWithoutAKeyAreLeftAlone() {
        #expect(MenuKey.parse("Show in Finder") == nil)
        #expect(MenuKey.parse("Show Info (beta)") == nil)  // one space: part of the title
        #expect(MenuKey.parse("X  (Unknown)") == nil)
    }
}
