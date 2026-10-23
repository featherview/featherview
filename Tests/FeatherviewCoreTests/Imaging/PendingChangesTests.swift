import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PendingChangesTests {
    let a = URL(fileURLWithPath: "/tmp/a.jpg")
    let b = URL(fileURLWithPath: "/tmp/b.jpg")

    @Test func rotateThenFlipShowsTheCombinedTransform() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.vertical))
        #expect(pending.transform == PictureTransform([.rotate(.clockwise), .flip(.vertical)]))
        #expect(pending.changes == [.rotate(.clockwise), .flip(.vertical)])
    }

    @Test func decodeOfTheRewrittenFileDropsTheWrittenChanges() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.vertical))
        pending.add(.rotate(.counterClockwise))
        pending.written(a)
        pending.written(a)
        pending.decoded(a)
        #expect(pending.changes == [.rotate(.counterClockwise)])
        // The written count is used up: the next decode of the same file drops everything left.
        pending.decoded(a)
        #expect(pending.changes.isEmpty)
    }

    @Test func decodeOfAnotherFileClearsAll() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.horizontal))
        pending.written(a)
        pending.decoded(b)
        #expect(pending.changes.isEmpty)
        #expect(pending.transform == PictureTransform())
    }

    @Test func decodeWithNothingWrittenClearsAll() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.decoded(a)
        #expect(pending.changes.isEmpty)
    }

    @Test func writesToAnotherFileStartCountingAgain() {
        var pending = PendingChanges()
        pending.written(b)
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.horizontal))
        pending.written(a)
        pending.decoded(a)
        #expect(pending.changes == [.flip(.horizontal)])
    }

    @Test func moreWrittenThanPendingDropsAll() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.written(a)
        pending.written(a)
        pending.decoded(a)
        #expect(pending.changes.isEmpty)
    }

    @Test func failureRemovesTheFirstUnwrittenChange() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.vertical))
        pending.add(.rotate(.counterClockwise))
        pending.written(a)
        #expect(pending.failed(a) == .flip(.vertical))
        #expect(pending.changes == [.rotate(.clockwise), .rotate(.counterClockwise)])
    }

    @Test func failureOfAnotherFilesWriteCountsNothingWritten() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.add(.flip(.vertical))
        pending.written(b)
        #expect(pending.failed(a) == .rotate(.clockwise))
        #expect(pending.changes == [.flip(.vertical)])
    }

    @Test func failureWithAllWrittenRemovesNothing() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.written(a)
        #expect(pending.failed(a) == nil)
        #expect(pending.changes == [.rotate(.clockwise)])
    }

    @Test func resetClearsChangesAndWrites() {
        var pending = PendingChanges()
        pending.add(.rotate(.clockwise))
        pending.written(a)
        pending.reset()
        #expect(pending.changes.isEmpty)
        pending.add(.flip(.horizontal))
        pending.add(.rotate(.clockwise))
        pending.written(a)
        pending.decoded(a)
        #expect(pending.changes == [.rotate(.clockwise)])
    }
}
