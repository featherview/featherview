import Testing
@testable import FeatherviewCore

@Suite struct BarsAutoHideTests {
    /// Enabled at 0, as the app starts it when the setting is on.
    private func enabled() -> BarsAutoHide {
        var machine = BarsAutoHide()
        machine.handle(.enabled(true), now: 0)
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

    @Test func pointerMoveShowsAgain() { expectShows(after: .pointerMoved) }
    @Test func topEdgeShowsAgain() { expectShows(after: .pointerAtTopEdge) }
    @Test func otherKeyShowsAgain() { expectShows(after: .key(browsing: false)) }

    private func expectShows(after event: BarsAutoHide.Event) {
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

    @Test func noHidingWhilePanelOpen() { expectNoHiding(while: .panelOpen(true), until: .panelOpen(false)) }
    @Test func noHidingOverBars() { expectNoHiding(while: .pointerOverBars(true), until: .pointerOverBars(false)) }
    @Test func fullScreenNeverHides() { expectNoHiding(while: .fullScreen(true), until: .fullScreen(false)) }

    private func expectNoHiding(while block: BarsAutoHide.Event, until unblock: BarsAutoHide.Event) {
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

        var wasHidden = hidden()
        wasHidden.handle(block, now: 4)
        #expect(wasHidden.barsVisible)
        #expect(wasHidden.hideAt == nil)
    }
}
