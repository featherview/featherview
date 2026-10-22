import Foundation
import Testing
import os
@testable import FeatherviewCore

@Suite struct FolderWatchTests {
    /// True when `stream` yields within `limit`. One use per stream: leaving it ends the stream.
    private func yields(_ stream: AsyncStream<Void>, within limit: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: limit); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func write(_ name: String, in dir: URL) throws {
        try Data("x".utf8).write(to: dir.appendingPathComponent(name))
    }

    @Test func addingAFileReports() async throws {
        let dir = try Fixtures.makeTempDir()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let made = FolderWatch(folder: dir, onChange: { continuation.yield() }, onGone: {})
        let watch = try #require(made)
        defer { watch.cancel() }
        try write("a.jpg", in: dir)
        #expect(await yields(stream, within: .seconds(1)))
    }

    @Test func burstReportsFew() async throws {
        let dir = try Fixtures.makeTempDir()
        let reports = OSAllocatedUnfairLock(initialState: 0)
        let made = FolderWatch(folder: dir, onChange: { reports.withLock { $0 += 1 } }, onGone: {})
        let watch = try #require(made)
        defer { watch.cancel() }
        for index in 0..<50 { try write("\(index).jpg", in: dir) }
        try await Task.sleep(for: .seconds(1))
        #expect((1...2).contains(reports.withLock { $0 }))
    }

    @Test func cancelStopsReports() async throws {
        let dir = try Fixtures.makeTempDir()
        let reports = OSAllocatedUnfairLock(initialState: 0)
        let made = FolderWatch(folder: dir, onChange: { reports.withLock { $0 += 1 } }, onGone: {})
        let watch = try #require(made)
        watch.cancel()
        watch.cancel()  // idempotent
        try write("a.jpg", in: dir)
        try await Task.sleep(for: .milliseconds(600))
        #expect(reports.withLock { $0 } == 0)
    }

    @Test func folderRenamedReportsGone() async throws {
        let parent = try Fixtures.makeTempDir()
        let dir = parent.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let made = FolderWatch(folder: dir, onChange: {}, onGone: { continuation.yield() })
        let watch = try #require(made)
        defer { watch.cancel() }
        try FileManager.default.moveItem(at: dir, to: parent.appendingPathComponent("moved"))
        #expect(await yields(stream, within: .seconds(1)))
    }

    @Test func missingFolderIsNil() throws {
        let dir = try Fixtures.makeTempDir().appendingPathComponent("missing")
        #expect(FolderWatch(folder: dir, onChange: {}, onGone: {}) == nil)
    }

    @Test func diffAddedRemoved() {
        let dir = URL(fileURLWithPath: "/tmp/fv")
        let (a, b, c, d) = (dir.appendingPathComponent("a.jpg"), dir.appendingPathComponent("b.jpg"),
                            dir.appendingPathComponent("c.jpg"), dir.appendingPathComponent("d.jpg"))
        let result = Arrivals.diff(listed: [a, b, c], scanned: [d, a, c])
        #expect(result.added == [d])
        #expect(result.removed == [b])
    }

    @Test func newestByModificationDate() {
        let dir = URL(fileURLWithPath: "/tmp/fv")
        let urls = ["a.jpg", "b.jpg", "c.jpg"].map { dir.appendingPathComponent($0) }
        let dates = [urls[0]: Date(timeIntervalSince1970: 300), urls[1]: Date(timeIntervalSince1970: 100),
                     urls[2]: Date(timeIntervalSince1970: 200)]
        #expect(Arrivals.newest(urls, modified: { dates[$0] }) == urls[0])
    }

    @Test func newestTieByName() {
        let dir = URL(fileURLWithPath: "/tmp/fv")
        let urls = ["img10.jpg", "img2.jpg", "img9.jpg"].map { dir.appendingPathComponent($0) }
        let same = Date(timeIntervalSince1970: 100)
        #expect(Arrivals.newest(urls, modified: { _ in same }) == urls[0])  // img10 is last in Finder order
        #expect(Arrivals.newest(urls, modified: { _ in nil }) == urls[0])
    }

    @Test func newestOfNoneIsNil() {
        #expect(Arrivals.newest([], modified: { _ in Date() }) == nil)
    }

    @Test func settledTrueForCompleteFile() async throws {
        let file = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        try Data("complete".utf8).write(to: file)
        #expect(await Arrivals.settled(file))
    }

    @Test func settledWaitsForGrowth() async throws {
        let file = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        try Data("first".utf8).write(to: file)
        let appended = OSAllocatedUnfairLock(initialState: false)
        // Its own thread, not a Task or GCD: under the full suite's load both start seconds late.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.15)
            let handle = try! FileHandle(forWritingTo: file)
            try! handle.seekToEnd()
            try! handle.write(contentsOf: Data("second".utf8))
            try! handle.close()
            appended.withLock { $0 = true }
        }
        // A sleep can overrun 30 s while the full suite fills every core; the growth is what this tests.
        let settled = await Arrivals.settled(file, timeout: .seconds(600))
        let appendedBefore = appended.withLock { $0 }
        #expect(settled)
        #expect(appendedBefore)
    }

    @Test func settledFalseForEmptyFileAtTimeout() async throws {
        let file = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        try Data().write(to: file)
        #expect(await Arrivals.settled(file, timeout: .milliseconds(300)) == false)
    }

    @Test func settledFalseWhenFileVanishes() async throws {
        let file = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        try Data("complete".utf8).write(to: file)
        let settled = Task { await Arrivals.settled(file) }
        try FileManager.default.removeItem(at: file)  // before the second read, however late the first one runs
        #expect(await settled.value == false)
    }
}
