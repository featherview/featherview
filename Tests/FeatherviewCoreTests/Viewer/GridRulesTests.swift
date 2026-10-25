import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct GridRulesTests {
    @Test func decodeSideRoundsUpTo128StepsCappedAt512() {
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
    }

    @Test func columnsFillTheWidth() {
        #expect(ThumbnailSize.columns(width: 1000, target: 128, gap: 12) == .init(count: 7, cell: 132))
        #expect(ThumbnailSize.columns(width: 1000, target: 256, gap: 12) == .init(count: 4, cell: 241))
        #expect(ThumbnailSize.columns(width: 300, target: 256, gap: 12) == .init(count: 2, cell: 144))  // 1 column: 300 > 256
    }

    @Test func columnsInANarrowWindow() {
        #expect(ThumbnailSize.columns(width: 50, target: 128, gap: 12) == .init(count: 1, cell: 50))
    }

    @Test func columnsWithoutWidth() {
        #expect(ThumbnailSize.columns(width: 0, target: 128, gap: 12) == .init(count: 1, cell: 128))
    }

    @Test func steppedTakesOneColumn() {
        #expect(ThumbnailSize.stepped(width: 1000, target: 128, gap: 12, larger: true) == 156)  // 6 columns
        #expect(ThumbnailSize.stepped(width: 1000, target: 128, gap: 12, larger: false) == 114)  // 8 columns
    }

    @Test func steppedStopsAtTheRange() {
        #expect(ThumbnailSize.stepped(width: 1000, target: 256, gap: 12, larger: true) == nil)  // 3 columns: 325
        #expect(ThumbnailSize.stepped(width: 1000, target: 64, gap: 12, larger: false) == nil)  // 14 columns: 60
    }

    @Test func pinchStepsKeepTheRemainder() {
        var pinch = PinchSteps()
        #expect(pinch.add(0.1) == 0)
        #expect(pinch.add(0.1) == 1)
        #expect(pinch.add(-0.4) == -2)
        pinch.end()
        #expect(pinch.add(0.1) == 0)
    }

    @Test func contextClickInsideSelectionKeepsIt() {
        #expect(GridSelection.contextClick(2, selection: [1, 2, 5]) == [1, 2, 5])
    }

    @Test func contextClickOutsideSelectionReplacesIt() {
        #expect(GridSelection.contextClick(3, selection: [1, 2, 5]) == [3])
    }

    @Test func plainClickInsideSeveralWaitsForMouseUp() {
        #expect(GridSelection.defersClick(2, selection: [1, 2], shift: false, command: false))
        #expect(!GridSelection.defersClick(2, selection: [2], shift: false, command: false))
        #expect(!GridSelection.defersClick(3, selection: [1, 2], shift: false, command: false))
        #expect(!GridSelection.defersClick(2, selection: [1, 2], shift: true, command: false))
        #expect(!GridSelection.defersClick(2, selection: [1, 2], shift: false, command: true))
    }

    @Test func cacheBudgetIsThreeOfTheLargestScreen() {
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

    // Mid-list: the next file; at the end: the one before; all gone: nothing.
    @Test(arguments: [([1, 2], 3), ([3, 4], 2), ([0, 1, 2, 3, 4], nil)] as [([Int], Int?)])
    func focusAfterRemovalPicksTheNextRemainingFile(_ removed: [Int], _ focus: Int?) {
        #expect(GridSelection.focusAfterRemoval(urls: urls, removed: Set(removed.map { urls[$0] })) == focus.map { urls[$0] })
    }

    @Test func indicesKeepSelectionByURL() {
        let x = URL(fileURLWithPath: "/x/x.jpg")
        let list = [urls[0], urls[2], urls[3]]
        #expect(GridSelection.indices(of: [urls[2], x], in: list) == IndexSet([1]))
    }

    // Past a few files the lookup takes another path: the same result.
    @Test func indicesOfALargeSelection() {
        let many = (0..<40).map { URL(fileURLWithPath: "/f/\($0).jpg") }
        let selected = Set(many.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) + [URL(fileURLWithPath: "/x/x.jpg")])
        #expect(GridSelection.indices(of: selected, in: many) == IndexSet(stride(from: 0, to: 40, by: 2)))
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
        ("\u{F70A}", [], .move), ("\u{F70B}", [], .copy), ("\u{F708}", [], .refresh), ("\u{F729}", [], .first), ("\u{F72B}", [], .last),
        ("b", [], .batch), ("+", [], .larger), ("+", .shift, .larger), ("=", [], .larger), ("-", [], .smaller),
        ("t", [], .toggle), ("o", [], .passOn(.open)), ("p", [], .passOn(.settings)),
        ("a", [], .passOn(.about)), ("m", [], .passOn(.minimize)), ("f", [], .passOn(.toggleFullScreen)),
        ("w", [], .passOn(.slideshow)), ("A", .shift, .passOn(.playInWindow)),
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
