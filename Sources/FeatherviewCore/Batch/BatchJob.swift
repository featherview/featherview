import Foundation
import os

public struct BatchJob: Sendable {
    public var inputs: [BatchInput]
    public var settings: BatchSettings

    public init(inputs: [BatchInput], settings: BatchSettings) {
        self.inputs = inputs
        self.settings = settings
    }
}

public enum BatchStatus: Sendable, Equatable { case converted, failed, notStarted }

public struct BatchResult: Sendable, Equatable {
    public let input: URL
    /// nil when failed or not started.
    public let output: URL?
    public let status: BatchStatus
    /// The error sentence, or a note such as "page 1 of 3".
    public let message: String?

    public init(input: URL, output: URL?, status: BatchStatus, message: String?) {
        self.input = input; self.output = output; self.status = status; self.message = message
    }

    /// "IMG_1.jpg → Holiday 001.heic", "Can't open broken.jpg", "… · page 1 of 3".
    public var logLine: String {
        let name = input.lastPathComponent
        switch status {
        case .failed: return message ?? String(localized: "Can't convert \(name)")
        case .notStarted: return String(localized: "\(name) wasn't converted")
        case .converted:
            let target = output?.lastPathComponent ?? ""
            if let message { return String(localized: "\(name) → \(target) · \(message)") }
            return String(localized: "\(name) → \(target)")
        }
    }
}

/// Stop / Pause / Resume, shared between the window and the running batch.
public final class BatchControl: Sendable {
    private struct State {
        var paused = false, stopped = false
        var pausedSince: ContinuousClock.Instant?
        var pausedTotal = Duration.zero
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func pause() {
        state.withLock {
            guard !$0.stopped, !$0.paused else { return }
            $0.paused = true
            $0.pausedSince = .now
        }
    }
    public func resume() { wake { Self.unpause(&$0) } }
    public func stop() { wake { $0.stopped = true; Self.unpause(&$0) } }
    public var isPaused: Bool { state.withLock { $0.paused } }
    public var isStopped: Bool { state.withLock { $0.stopped } }

    /// Time spent paused so far, including a pause still going on (time left leaves it out).
    public func pausedDuration() -> Duration {
        state.withLock { s in s.pausedTotal + (s.pausedSince.map { .now - $0 } ?? .zero) }
    }

    private static func unpause(_ s: inout State) {
        if let since = s.pausedSince { s.pausedTotal += .now - since }
        s.pausedSince = nil
        s.paused = false
    }

    /// Returns once not paused (or stopped).
    func waitWhilePaused() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let waiting = state.withLock { s in
                guard s.paused, !s.stopped else { return false }
                s.waiters.append(waiter)
                return true
            }
            if !waiting { waiter.resume() }
        }
    }

    private func wake(_ change: @Sendable (inout State) -> Void) {
        let waiters = state.withLock { s in
            change(&s)
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}

public enum BatchLog {
    /// One line per result, then "N converted, M failed" (and ", K not converted" after a Stop).
    public static func text(_ results: [BatchResult]) -> String {
        let converted = results.filter { $0.status == .converted }.count
        let failed = results.filter { $0.status == .failed }.count
        let notStarted = results.count - converted - failed
        let summary = notStarted > 0
            ? String(localized: "\(converted) converted, \(failed) failed, \(notStarted) not converted")
            : String(localized: "\(converted) converted, \(failed) failed")
        return (results.map(\.logLine) + [summary]).joined(separator: "\n")
    }
}
