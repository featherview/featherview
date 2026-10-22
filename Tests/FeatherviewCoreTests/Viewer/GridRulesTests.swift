import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct GridRulesTests {
    @Test func decodeSideSteps() {
        #expect(ThumbnailSize.decodeSide(points: 128, scale: 2) == 256)
        #expect(ThumbnailSize.decodeSide(points: 100, scale: 1) == 128)
        #expect(ThumbnailSize.decodeSide(points: 129, scale: 2) == 384)
        #expect(ThumbnailSize.decodeSide(points: 256, scale: 2) == 512)
        #expect(ThumbnailSize.decodeSide(points: 256, scale: 3) == 512)
    }

    @Test func steppedClamps() {
        #expect(ThumbnailSize.stepped(128, larger: true) == 160)
        #expect(ThumbnailSize.stepped(250, larger: true) == 256)
        #expect(ThumbnailSize.stepped(64, larger: false) == 64)
        #expect(ThumbnailSize.standard == 128)
        #expect(ThumbnailSize.range == 64...256)
    }

    @Test func cacheBudgetThreeScreens() {
        let screens = [PixelSize(width: 3024, height: 1964), PixelSize(width: 1920, height: 1080)]
        #expect(ThumbnailSize.cacheBudget(screens: screens) == 3 * 3024 * 1964 * 4)
    }

    @Test func wantedVisibleFirstThenAhead() {
        #expect(GridWindow.wanted(visible: 40..<80, count: 10_000, forward: true) == Array(40...79) + Array(80...119))
        #expect(GridWindow.wanted(visible: 40..<80, count: 10_000, forward: false)
            == Array(40...79) + Array((0...39).reversed()))
    }

    @Test(arguments: [(0..<40, 10_000, true), (40..<80, 10_000, false), (9_960..<10_000, 10_000, true),
                      (0..<0, 0, true), (0..<5, 5, false), (100..<300, 10_000, true)])
    func wantedIsBoundedToTwoScreens(_ visible: Range<Int>, _ count: Int, _ forward: Bool) {
        let wanted = GridWindow.wanted(visible: visible, count: count, forward: forward)
        #expect(wanted.count <= 2 * visible.count)
        #expect(Set(wanted).count == wanted.count)
        #expect(wanted.allSatisfy { (0..<count).contains($0) })
    }

    @Test func wantedClipsAtEnds() {
        #expect(GridWindow.wanted(visible: 9_990..<10_000, count: 10_000, forward: true) == Array(9_990..<10_000))
    }

    private let urls = ["a", "b", "c", "d", "e"].map { URL(fileURLWithPath: "/x/\($0).jpg") }

    @Test func focusAfterRemovalMidList() {
        #expect(GridSelection.focusAfterRemoval(urls: urls, removed: [urls[1], urls[2]]) == urls[3])
    }

    @Test func focusAfterRemovingTheEnd() {
        #expect(GridSelection.focusAfterRemoval(urls: urls, removed: [urls[3], urls[4]]) == urls[2])
    }

    @Test func focusAfterRemovingAll() {
        #expect(GridSelection.focusAfterRemoval(urls: urls, removed: Set(urls)) == nil)
    }

    @Test func indicesKeepSelectionByURL() {
        let x = URL(fileURLWithPath: "/x/x.jpg")
        let list = [urls[0], urls[2], urls[3]]
        #expect(GridSelection.indices(of: [urls[2], x], in: list) == IndexSet([1]))
    }

    @Test func shiftClickRangesFromTheAnchor() {
        let click = GridSelection.click(4, in: urls, selection: [1], anchor: urls[1], shift: true, command: false)
        #expect(click.selection == [1, 2, 3, 4])
        #expect(click.anchor == urls[1])
    }

    @Test func shiftClickReplacesTheLastRange() {
        let first = GridSelection.click(4, in: urls, selection: [1], anchor: urls[1], shift: true, command: false)
        let second = GridSelection.click(2, in: urls, selection: first.selection, anchor: first.anchor, shift: true, command: false)
        #expect(second.selection == [1, 2])
    }

    @Test func shiftClickFollowsTheAnchorsFileWhenTheListChanges() {
        let shrunk = [urls[0], urls[3], urls[4]]
        #expect(GridSelection.click(0, in: shrunk, selection: [], anchor: urls[4], shift: true, command: false).selection == [0, 1, 2])
        let gone = GridSelection.click(0, in: shrunk, selection: [], anchor: urls[2], shift: true, command: false)
        #expect(gone.selection == [0])
        #expect(gone.anchor == shrunk[0])
    }

    @Test func plainAndCommandClicks() {
        let plain = GridSelection.click(3, in: urls, selection: [0, 1], anchor: urls[0], shift: false, command: false)
        #expect(plain.selection == [3])
        #expect(plain.anchor == urls[3])
        #expect(GridSelection.click(1, in: urls, selection: [0, 1], anchor: urls[0], shift: false, command: true).selection == [0])
        let added = GridSelection.click(3, in: urls, selection: [0], anchor: urls[0], shift: false, command: true)
        #expect(added.selection == [0, 3])
        #expect(added.anchor == urls[3])
    }

    @Test(arguments: [
        ("\r", MenuKey.Modifiers(), GridKey.view), ("\u{3}", [], .view), ("\u{1B}", [], .leave),
        (" ", [], .quickLook), ("\u{F728}", [], .trash), ("\u{7F}", .command, .trash),
        ("\u{F70A}", [], .move), ("\u{F70B}", [], .copy), ("\u{F729}", [], .first), ("\u{F72B}", [], .last),
        ("b", [], .batch), ("+", [], .larger), ("+", .shift, .larger), ("=", [], .larger), ("-", [], .smaller),
        ("t", [], .toggle), ("o", [], .passOn(.open)), ("p", [], .passOn(.settings)),
        ("a", [], .passOn(.about)), ("m", [], .passOn(.minimize)), ("f", [], .passOn(.toggleFullScreen)),
    ] as [(String, MenuKey.Modifiers, GridKey)])
    func gridKeys(_ characters: String, _ modifiers: MenuKey.Modifiers, _ key: GridKey) {
        #expect(GridKey.action(characters: characters, modifiers: modifiers) == key)
    }

    @Test(arguments: [
        ("\u{7F}", MenuKey.Modifiers()), ("r", []), ("l", []), ("i", []), ("0", []), ("1", []), ("s", []),
        ("g", []), ("B", .shift), ("b", .command), ("\u{F703}", []), ("\u{F701}", []), ("\u{F703}", .option),
    ] as [(String, MenuKey.Modifiers)])
    func keysTheGridLeavesAlone(_ characters: String, _ modifiers: MenuKey.Modifiers) {
        #expect(GridKey.action(characters: characters, modifiers: modifiers) == nil)
    }
}
