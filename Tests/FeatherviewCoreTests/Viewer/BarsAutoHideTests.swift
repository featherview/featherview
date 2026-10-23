import Testing
@testable import FeatherviewCore

@Suite struct BarsAutoHideTests {
    /// Enabled at 0 in the key window, a picture shown, the pointer over it.
    private func enabled() -> BarsAutoHide {
        var machine = BarsAutoHide()
        machine.handle(.enabled(true), now: 0)
        machine.handle(.windowKey(true), now: 0)
        machine.handle(.pictureShown(true), now: 0)
        machine.handle(.pointerOverBars(false), now: 0)
        return machine
    }

    /// Enabled and already hidden at 2.
    private func hidden() -> BarsAutoHide {
        var machine = enabled()
        machine.handle(.pointerMoved, now: 0)
        machine.handle(.tick, now: 2)
        return machine
    }

    @Test func startsVisibleWithoutTimer() {
        let machine = BarsAutoHide()
        #expect(machine.barsVisible)
        #expect(machine.hideAt == nil)
    }

    @Test func noTimerUntilThePointerIsOverThePicture() {
        var machine = BarsAutoHide()
        machine.handle(.enabled(true), now: 0)
        machine.handle(.windowKey(true), now: 0)
        machine.handle(.key(browsing: false), now: 0)
        #expect(machine.hideAt == nil)
        machine.handle(.tick, now: 10)
        #expect(machine.barsVisible)
    }

    @Test func hidesAfterTheRest() {
        var machine = enabled()
        machine.handle(.pointerMoved, now: 0)
        #expect(machine.hideAt == 2)
        machine.handle(.tick, now: 2)
        #expect(machine.barsVisible == false)
    }

    @Test func tickBeforeTheRestDoesNothing() {
        var machine = enabled()
        machine.handle(.pointerMoved, now: 0)
        machine.handle(.pointerMoved, now: 1.5)
        #expect(machine.hideAt == 3.5)
        machine.handle(.tick, now: 2)
        #expect(machine.barsVisible)
    }

    @Test(arguments: [BarsAutoHide.Event.pointerMoved, .pointerAtTopEdge, .key(browsing: false)])
    func hiddenBarsShowAgainOn(_ event: BarsAutoHide.Event) {
        var machine = hidden()
        #expect(machine.barsVisible == false)
        machine.handle(event, now: 4)
        #expect(machine.barsVisible)
        #expect(machine.hideAt == 6)
    }

    @Test func browsingKeysKeepHidden() {
        var machine = hidden()
        machine.handle(.key(browsing: true), now: 4)
        #expect(machine.barsVisible == false)
        #expect(machine.hideAt == nil)
    }

    /// Browsing onto a file that can't be decoded: no picture, but only browsing keys were pressed.
    @Test func browsingOntoABadFileKeepsHidden() {
        var machine = hidden()
        machine.handle(.key(browsing: true), now: 4)
        machine.handle(.pictureShown(false), now: 4)
        #expect(machine.barsVisible == false)
        #expect(machine.hideAt == nil)
        machine.handle(.key(browsing: true), now: 5)
        machine.handle(.pictureShown(true), now: 5)
        #expect(machine.barsVisible == false)
        #expect(machine.hideAt == nil)
        machine.handle(.pictureShown(false), now: 6)
        machine.handle(.pointerMoved, now: 7)
        #expect(machine.barsVisible)
    }

    @Test func browsingKeyWhileVisibleRestartsTheRest() {
        var machine = enabled()
        machine.handle(.key(browsing: true), now: 5)
        #expect(machine.barsVisible)
        #expect(machine.hideAt == 7)
    }

    @Test func disabledNeverHides() {
        var machine = BarsAutoHide()
        machine.handle(.enabled(false), now: 0)
        machine.handle(.pointerMoved, now: 0)
        machine.handle(.tick, now: 10)
        #expect(machine.barsVisible)
        #expect(machine.hideAt == nil)

        var wasHidden = hidden()
        wasHidden.handle(.enabled(false), now: 4)
        #expect(wasHidden.barsVisible)
        #expect(wasHidden.hideAt == nil)
    }

    /// No picture: the empty window, "No images in…" or a full-window error leave nothing to rest the pointer over.
    @Test(arguments: [
        (BarsAutoHide.Event.windowKey(false), BarsAutoHide.Event.windowKey(true)), (.panelOpen(true), .panelOpen(false)),
        (.pointerOverBars(true), .pointerOverBars(false)), (.pictureShown(false), .pictureShown(true)),
        (.fullScreen(true), .fullScreen(false)),
    ])
    func noHidingWhile(_ block: BarsAutoHide.Event, until unblock: BarsAutoHide.Event) {
        var machine = enabled()
        machine.handle(.pointerMoved, now: 0)
        machine.handle(block, now: 1)
        #expect(machine.hideAt == nil)
        machine.handle(.pointerMoved, now: 1.5)
        machine.handle(.key(browsing: true), now: 1.6)
        machine.handle(.tick, now: 10)
        #expect(machine.barsVisible)
        #expect(machine.hideAt == nil)
        machine.handle(unblock, now: 12)
        #expect(machine.barsVisible)
        #expect(machine.hideAt == 14)

        guard block != .pictureShown(false) else { return }  // browsingOntoABadFileKeepsHidden
        var wasHidden = hidden()
        wasHidden.handle(block, now: 4)
        #expect(wasHidden.barsVisible)
        #expect(wasHidden.hideAt == nil)
    }
}
