import Foundation

/// How each item of a drop brings its file: Finder's carry a file URL, Photos' a file promise.
public enum DropItem: Equatable, Sendable {
    /// Taken as the file URL it carries.
    case file
    /// Received through the n-th promise on the pasteboard (one per item with a promise type).
    case promise(Int)
    case skipped

    /// An item with a file URL is never received again through a promise it also offers.
    public static func plan(_ itemTypes: [[String]], fileURLType: String, promiseTypes: Set<String>) -> [DropItem] {
        var promises = 0
        return itemTypes.map { types in
            let isPromise = types.contains(where: promiseTypes.contains)
            defer { if isPromise { promises += 1 } }
            if types.contains(fileURLType) { return .file }
            return isPromise ? .promise(promises) : .skipped
        }
    }

    /// `folder`, created empty: a folder left from an earlier launch holds someone else's drop, which browsing
    /// would show too. Touches the disk, so call it off the main thread.
    public static func freshFolder(_ folder: URL) -> URL? {
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// The promised files `start` reports through its `add` (the item's drop index and the file, nil when it
    /// failed) together with `files`, in the drop's order, once `expected` reports came in, or once none came
    /// for `quiet` seconds: a promise whose reader is never called (Photos quit during an iCloud download)
    /// mustn't keep the drop, and with it the batch list, waiting forever.
    public nonisolated(nonsending) static func collect(_ files: [(index: Int, url: URL)], expected: Int, quiet: TimeInterval,
                                                       start: (@escaping @Sendable (Int, URL?) -> Void) -> Void) async -> [URL] {
        await withCheckedContinuation { continuation in
            let arrivals = Arrivals(files: files, expected: expected, quiet: quiet, continuation: continuation)
            start(arrivals.add)
            arrivals.wait()
        }
    }

    /// Collects promised files as they arrive, on any thread; resumes once.
    private final class Arrivals: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [(index: Int, url: URL)]
        private var left: Int
        private var reports = 0
        private let quiet: TimeInterval
        private var continuation: CheckedContinuation<[URL], Never>?

        init(files: [(index: Int, url: URL)], expected: Int, quiet: TimeInterval,
             continuation: CheckedContinuation<[URL], Never>) {
            self.files = files
            left = expected
            self.quiet = quiet
            self.continuation = continuation
        }

        func add(_ index: Int, _ url: URL?) {
            lock.withLock {
                guard continuation != nil else { return }
                if let url { files.append((index, url)) }
                left -= 1
                reports += 1
            }
            finish { left <= 0 }
            wait()
        }

        /// Finishes with what has arrived unless another report comes within `quiet` seconds.
        func wait() {
            let seen = lock.withLock { reports }
            DispatchQueue.global().asyncAfter(deadline: .now() + quiet) { [self] in
                finish { reports == seen }
            }
        }

        private func finish(when isDone: () -> Bool) {
            let done: (CheckedContinuation<[URL], Never>, [URL])? = lock.withLock {
                guard let continuation, isDone() else { return nil }
                self.continuation = nil
                // Stable sort: files of one promise keep their arrival order.
                return (continuation, files.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }
                    .map(\.element.url))
            }
            done.map { $0.0.resume(returning: $0.1) }
        }
    }
}
