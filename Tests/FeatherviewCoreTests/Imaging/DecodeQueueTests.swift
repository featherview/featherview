import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct DecodeQueueTests {
    private let urls = (0..<5).map { URL(fileURLWithPath: "/tmp/\($0).jpg") }

    /// Occupies one of the queue's threads until `release`, so later jobs wait.
    private func block(_ queue: DecodeQueue, _ url: URL) async -> (task: Task<Void, Error>, release: DispatchSemaphore) {
        let release = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let task = Task { try await queue.run(url) { started.signal(); release.wait() } }
        await withCheckedContinuation { done in DispatchQueue.global().async { started.wait(); done.resume() } }
        return (task, release)
    }

    private func waitUntil(_ queue: DecodeQueue, waiting count: Int) async {
        while queue.waitingCount < count { await Task.yield() }
    }

    @Test func runsNearestFirst() async throws {
        let queue = DecodeQueue(width: 1)
        queue.focus([urls[0], urls[1], urls[2], urls[3]])
        let blocker = await block(queue, urls[0])
        let order = OrderLog()
        var jobs: [Task<Void, Error>] = []
        for url in [urls[3], urls[1], urls[2]] {
            jobs.append(Task { try await queue.run(url) { order.append(url) } })
            await waitUntil(queue, waiting: jobs.count)
        }
        blocker.release.signal()
        for job in jobs { try await job.value }
        #expect(order.urls == [urls[1], urls[2], urls[3]])
    }

    @Test func aMoveReranksWaitingJobs() async throws {
        let queue = DecodeQueue(width: 1)
        queue.focus([urls[0], urls[1], urls[2]])
        let blocker = await block(queue, urls[0])
        let order = OrderLog()
        let near = Task { try await queue.run(urls[1]) { order.append(urls[1]) } }
        await waitUntil(queue, waiting: 1)
        let far = Task { try await queue.run(urls[2]) { order.append(urls[2]) } }
        await waitUntil(queue, waiting: 2)
        queue.focus([urls[2], urls[1]])  // moved on: 2 is now current
        blocker.release.signal()
        try await near.value
        try await far.value
        #expect(order.urls == [urls[2], urls[1]])
    }

    @Test func aMoveDropsWaitingJobsOutsideTheWindow() async throws {
        let queue = DecodeQueue(width: 1)
        queue.focus([urls[0], urls[1], urls[2]])
        let blocker = await block(queue, urls[0])
        let ran = OrderLog()
        let dropped = Task { try await queue.run(urls[1]) { ran.append(urls[1]) } }
        await waitUntil(queue, waiting: 1)
        queue.focus([urls[2], urls[3]])
        await #expect(throws: CancellationError.self) { try await dropped.value }
        #expect(queue.waitingCount == 0)
        // The running job outside the window finishes: ImageIO can't be stopped.
        blocker.release.signal()
        try await blocker.task.value
        #expect(ran.urls.isEmpty)
    }

    @Test func jobsOutsideTheWindowAreRefused() async throws {
        let queue = DecodeQueue()
        queue.focus([urls[0]])
        await #expect(throws: CancellationError.self) { try await queue.run(urls[1]) { 1 } }
        #expect(try await queue.run(urls[0]) { 1 } == 1)
        #expect(queue.wants(urls[0]))
        #expect(!queue.wants(urls[1]))
    }

    @Test func withoutAWindowEverythingRuns() async throws {
        let queue = DecodeQueue()
        #expect(try await queue.run(urls[4]) { 4 } == 4)
        #expect(queue.wants(urls[4]))
    }

    @Test func cancellingAWaitingCallerSkipsItsJob() async throws {
        let queue = DecodeQueue(width: 1)
        let blocker = await block(queue, urls[0])
        let ran = OrderLog()
        let waiter = Task { try await queue.run(urls[1]) { ran.append(urls[1]) } }
        await waitUntil(queue, waiting: 1)
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        blocker.release.signal()
        try await blocker.task.value
        #expect(ran.urls.isEmpty)
    }

    @Test func errorsReachTheCaller() async {
        let url = urls[0]
        await #expect(throws: DecodeError.self) {
            try await DecodeQueue().run(url) { () throws -> Int in throw DecodeError.unreadable(url) }
        }
    }

    @Test func runsUpToWidthAtOnce() async throws {
        let queue = DecodeQueue(width: 2)
        let first = await block(queue, urls[0])
        let second = await block(queue, urls[1])  // would hang if the second had to wait for the first
        first.release.signal()
        second.release.signal()
        try await first.task.value
        try await second.task.value
    }
}

private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URL] = []
    func append(_ url: URL) { lock.withLock { log.append(url) } }
    var urls: [URL] { lock.withLock { log } }
}
