import Observation
import Testing
@testable import FeatherviewCore

@MainActor @Suite struct LastUsedTests {
    final class Viewer {}
    let main = Viewer()
    let extra = Viewer()

    @Test func startsWithTheFallback() {
        #expect(LastUsed(fallback: main).current === main)
    }

    @Test func closingTheLastUsedOneFallsBackToTheMainOne() {
        // An extra window used last, then closed: ⌘O from the Batch window still opens in the main viewer.
        let last = LastUsed(fallback: main)
        last.use(extra)
        #expect(last.current === extra)
        last.close(extra)
        #expect(last.current === main)
    }

    @Test func closingAnotherOneKeepsTheLastUsed() {
        let last = LastUsed(fallback: main)
        last.use(extra)
        last.close(Viewer())
        #expect(last.current === extra)
    }

    @Test func viewsReadingItAreToldWhenItChanges() {
        // The Batch window's "Use Viewer's Folder" must redraw when the user switches viewers.
        let last = LastUsed(fallback: main)
        nonisolated(unsafe) var changes = 0  // onChange runs synchronously in the mutation here
        withObservationTracking { _ = last.current } onChange: { changes += 1 }
        last.use(extra)
        #expect(changes == 1)
        withObservationTracking { _ = last.current } onChange: { changes += 1 }
        last.close(extra)
        #expect(changes == 2)
    }
}
