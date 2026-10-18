import Foundation
import os

/// Runs blocking decodes on its own threads, at most `width` at once, nearest to the image shown first.
/// ImageIO blocks its thread until done; on Swift's cooperative pool (one thread per core) stale prefetches
/// would hold every thread while the image the user wants waits.
///
/// The window (`focus`) is the files wanted now, in order: current, then its neighbours nearest first, ahead of
/// the browsing direction before behind. A move drops waiting jobs outside the new window and reorders the rest.
/// A running job can't be stopped and finishes; `wants` tells its caller whether the result is still worth keeping.
public final class DecodeQueue: Sendable {
    private struct Job: Sendable {
        let id: Int
        let url: URL
        let start: @Sendable () -> Void
        let drop: @Sendable () -> Void
    }

    private struct State: Sendable {
        var window: [URL: Int]?  // rank per file; nil: no window yet, everything runs in order of arrival
        var waiting: [Job] = []
        var running = 0
        var nextID = 0

        func rank(_ job: Job) -> Int { window?[job.url] ?? 0 }
    }

    private let width: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let threads = DispatchQueue(label: "net.mynetx.featherview.decode", qos: .userInitiated, attributes: .concurrent)

    /// shortcut: 3 decodes at once, measured against 2 on a 10-core M1 Pro (plan Task 6); measure again on a Mac with fewer cores.
    public init(width: Int = 3) {
        self.width = width
    }

    /// Sets the files wanted now, nearest first (the first is the one shown); `nil` lifts the window.
    /// Waiting jobs for other files are dropped: their callers get `CancellationError`.
    public func focus(_ urls: [URL]?) {
        let dropped = state.withLock { state in
            state.window = urls.map { Dictionary($0.enumerated().map { ($1, $0) }, uniquingKeysWith: min) }
            guard let window = state.window else { return [Job]() }
            let dropped = state.waiting.filter { window[$0.url] == nil }
            state.waiting.removeAll { window[$0.url] == nil }
            return dropped
        }
        dropped.forEach { $0.drop() }
        pump()
    }

    /// True if `url` is in the window (or there is none): a decode of it that just finished is worth keeping.
    public func wants(_ url: URL) -> Bool {
        state.withLock { $0.window.map { $0[url] != nil } ?? true }
    }

    /// Runs `work` for `url` on the queue's threads, once the jobs ranked before it have started.
    /// Throws `CancellationError` without running it if the caller is cancelled or `url` leaves the window first.
    public func run<T: Sendable>(_ url: URL, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let job = Job(id: id, url: url,
                              start: { continuation.resume(with: Result { try work() }) },
                              drop: { continuation.resume(throwing: CancellationError()) })
                // Checked under the lock: a cancel handler that ran before this found nothing to drop.
                let queued = state.withLock { state in
                    guard !Task.isCancelled, state.window.map({ $0[url] != nil }) ?? true else { return false }
                    state.waiting.append(job)
                    return true
                }
                if queued { pump() } else { job.drop() }
            }
        } onCancel: {
            let dropped = state.withLock { state in
                state.waiting.firstIndex { $0.id == id }.map { state.waiting.remove(at: $0) }
            }
            dropped?.drop()
        }
        return result
    }

    /// Starts the best waiting jobs while threads are free: lowest rank first, then oldest.
    private func pump() {
        let starting = state.withLock { state in
            var starting: [Job] = []
            while state.running < width, !state.waiting.isEmpty {
                let best = state.waiting.indices.min { (state.rank(state.waiting[$0]), $0) < (state.rank(state.waiting[$1]), $1) }!
                starting.append(state.waiting.remove(at: best))
                state.running += 1
            }
            return starting
        }
        for job in starting {
            threads.async {
                job.start()
                self.state.withLock { $0.running -= 1 }
                self.pump()
            }
        }
    }
}

extension DecodeQueue {
    var waitingCount: Int { state.withLock { $0.waiting.count } }
}
