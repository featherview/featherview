import Foundation
import os

/// Watches one folder's entries (its vnode): files added, removed or renamed inside it, and the folder
/// itself going away. Runs only while someone follows the folder, so browsing pays nothing.
// shortcut: network volumes don't report remote changes to vnode sources, poll there if people follow folders on servers.
public final class FolderWatch: Sendable {
    private struct State: Sendable {
        var source: DispatchSourceFileSystemObject?
        var generation = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let queue: DispatchQueue

    /// Nil when the folder can't be opened. `onChange` comes once the folder has been quiet for `quiet`
    /// (a burst is one report); `onGone` when the folder is renamed or deleted, after which the watch stops.
    /// Both run on the watch's own serial queue.
    public init?(folder: URL, quiet: Duration = .milliseconds(200),
                 onChange: @escaping @Sendable () -> Void, onGone: @escaping @Sendable () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let queue = DispatchQueue(label: "net.mynetx.featherview.FolderWatch.\(UUID().uuidString)")
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                               queue: queue)
        self.queue = queue
        state = OSAllocatedUnfairLock(initialState: State(source: source))
        let delay = DispatchTimeInterval.nanoseconds(Int(quiet / .nanoseconds(1)))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                guard stop() else { return }
                onGone()
                return
            }
            let generation = state.withLock { state in
                state.generation += 1
                return state.generation
            }
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, state.withLock({ $0.source != nil && $0.generation == generation }) else { return }
                onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { cancel() }

    /// Idempotent; no callback runs after it returns.
    public func cancel() {
        stop()
        // Wait out a callback already running, unless this is that callback.
        if String(cString: __dispatch_queue_get_label(nil)) != queue.label { queue.sync {} }
    }

    /// True when this call stopped the source.
    @discardableResult private func stop() -> Bool {
        let source = state.withLock { state in
            defer { state.source = nil }
            return state.source
        }
        source?.cancel()
        return source != nil
    }
}

/// What arrived in a followed folder, and when an arrival is complete.
public enum Arrivals {
    /// By URL: `added` in `scanned` order, `removed` in `listed` order.
    public static func diff(listed: [URL], scanned: [URL]) -> (added: [URL], removed: [URL]) {
        let listedSet = Set(listed), scannedSet = Set(scanned)
        return (scanned.filter { !listedSet.contains($0) }, listed.filter { !scannedSet.contains($0) })
    }

    /// The latest modification date; ties and missing dates by Finder name order, last wins.
    public static func newest(_ added: [URL], modified: (URL) -> Date?) -> URL? {
        var best: (url: URL, date: Date)?
        for url in FolderScanner.inFinderOrder(added) {
            let date = modified(url) ?? .distantPast
            if best == nil || date >= best!.date { best = (url, date) }
        }
        return best?.url
    }

    /// True once the file's size is non-zero and unchanged between two reads `interval` apart (a file
    /// still being copied or exported isn't complete); false at `timeout`, when the file is gone, or on cancel.
    public static func settled(_ url: URL, interval: Duration = .milliseconds(250),
                               timeout: Duration = .seconds(30)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        guard var previous = size(of: url) else { return false }
        while true {
            do { try await Task.sleep(for: interval) } catch { return false }
            guard let current = size(of: url) else { return false }
            if current > 0, current == previous { return true }
            // Checked after the read, so a sleep that overran the deadline still gets its answer.
            if clock.now + interval > deadline { return false }
            previous = current
        }
    }

    private static func size(of url: URL) -> Int64? {
        var info = stat()
        return stat(url.path, &info) == 0 ? Int64(info.st_size) : nil
    }
}
