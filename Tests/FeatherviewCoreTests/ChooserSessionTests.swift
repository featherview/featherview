import Foundation
import Testing
@testable import FeatherviewCore

/// root/ a/ (a1/ a2/)  b/
private func makeTree() throws -> URL {
    let root = try Fixtures.makeTempDir()
    for folder in ["a/a1", "a/a2", "b"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    return root
}

/// Keys are sent without waiting, as a fast typist does while a listing still runs.
@MainActor @Suite struct ChooserSessionTests {
    @Test func movesApplyAfterTheListingBeforeThem() async throws {
        let session = ChooserSession()
        session.start(folder: try makeTree(), includeHidden: false)  // selects a
        session.enter()  // lists a, selects a1
        session.move(1)
        await session.settled()
        #expect(session.chooser?.folder.lastPathComponent == "a")
        #expect(session.chooser?.selected.url.lastPathComponent == "a2")
    }

    @Test func enterUsesTheSelectionAfterEarlierMoves() async throws {
        let session = ChooserSession()
        session.start(folder: try makeTree(), includeHidden: false)
        session.move(1)  // a → b
        session.enter()
        await session.settled()
        #expect(session.chooser?.folder.lastPathComponent == "b")
    }

    @Test func openWaitsForQueuedKeys() async throws {
        let session = ChooserSession()
        var opened: URL?
        session.start(folder: try makeTree(), includeHidden: false)
        session.enter()
        session.move(1)
        session.open { opened = $0 }
        await session.settled()
        #expect(opened?.lastPathComponent == "a2")
    }

    @Test func isOpenBeforeTheFirstListingAndCloseDropsIt() async throws {
        let session = ChooserSession()
        session.start(folder: try makeTree(), includeHidden: false)
        #expect(session.isOpen)
        session.close()
        await session.settled()
        #expect(!session.isOpen)
        #expect(session.chooser == nil)
    }
}
