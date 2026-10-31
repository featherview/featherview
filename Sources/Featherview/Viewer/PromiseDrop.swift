import AppKit
import UniformTypeIdentifiers

/// Drops that bring files, either as file URLs (Finder) or as file promises (Photos, Mail).
@MainActor
enum PromiseDrop {
    /// What a drop target accepts: file URLs and file promises.
    static let types: [UTType] = [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map {
        UTType($0) ?? UTType(importedAs: $0)
    }

    private static var drops = 0
    private static let queue = OperationQueue()

    /// The dropped files: file URLs as they are, promised files received into a new
    /// `Caches/net.mynetx.featherview/Dropped/<n>` folder. Files that fail to arrive are left out.
    static func receive(_ providers: [NSItemProvider]) async -> [URL] {
        // Read before the first suspension, while the drag pasteboard still holds this drop.
        // A promise item carries no file URL yet, so the promises are exactly the items without one.
        let receivers = NSPasteboard(name: .drag).readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        var urls: [URL] = []
        for provider in fileProviders {
            if let url = await fileURL(provider) { urls.append(url) }
        }
        guard !receivers.isEmpty, let folder = newFolder() else { return urls }
        return urls + (await receive(receivers, into: folder))
    }

    private static func fileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private static func newFolder() -> URL? {
        drops += 1
        let folder = URL.cachesDirectory.appending(path: "net.mynetx.featherview/Dropped/\(drops)", directoryHint: .isDirectory)
        // A folder left from an earlier launch holds someone else's drop; browsing would show it too.
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// Receives every promise at once and returns the files in the drop's order.
    private static func receive(_ receivers: [NSFilePromiseReceiver], into folder: URL) async -> [URL] {
        let counts = receivers.map { max($0.fileTypes.count, 1) }
        return await withCheckedContinuation { continuation in
            let arrivals = Arrivals(expected: counts.reduce(0, +), continuation: continuation)
            for (index, receiver) in receivers.enumerated() {
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                    arrivals.add(index, error == nil ? url : nil)
                }
            }
        }
    }

    /// Collects promised files as they arrive, on the receive queue.
    private final class Arrivals: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [(index: Int, url: URL)] = []
        private var left: Int
        private let continuation: CheckedContinuation<[URL], Never>

        init(expected: Int, continuation: CheckedContinuation<[URL], Never>) {
            left = expected
            self.continuation = continuation
        }

        func add(_ index: Int, _ url: URL?) {
            let done: [URL]? = lock.withLock {
                if let url { files.append((index, url)) }
                left -= 1
                guard left == 0 else { return nil }
                // Stable sort: files of one promise keep their arrival order.
                return files.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }.map(\.element.url)
            }
            if let done { continuation.resume(returning: done) }
        }
    }
}
