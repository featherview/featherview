import AppKit
import FeatherviewCore
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

    /// The dropped files in the drop's order: file URLs as they are, promises of items without a file URL
    /// received into a new `Caches/net.mynetx.featherview/Dropped/<n>` folder. Files that fail to arrive are
    /// left out. Reads the drag pasteboard at once, so call it from the drop handler, before any suspension.
    static func receive() -> Task<[URL], Never> {
        let pasteboard = NSPasteboard(name: .drag)
        let items = pasteboard.pasteboardItems ?? []
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        let plan = DropItem.plan(items.map { $0.types.map(\.rawValue) }, fileURLType: NSPasteboard.PasteboardType.fileURL.rawValue,
                                 promiseTypes: Set(NSFilePromiseReceiver.readableDraggedTypes))
        var files: [(index: Int, url: URL)] = []
        var promised: [(index: Int, receiver: NSFilePromiseReceiver)] = []
        for (index, (item, how)) in zip(items, plan).enumerated() {
            switch how {
            case .file:
                // Finder's are file reference URLs (file:///.file/id=…); filePathURL makes them paths.
                if let url = item.string(forType: .fileURL).flatMap(NSURL.init(string:))?.filePathURL { files.append((index, url)) }
            case .promise(let n) where n < receivers.count: promised.append((index, receivers[n]))
            default: break
            }
        }
        return Task {
            guard !promised.isEmpty, let folder = newFolder() else { return files.map(\.url) }
            return await receive(promised, into: folder, with: files)
        }
    }

    private static func newFolder() -> URL? {
        drops += 1
        let folder = BatchSettings.droppedCache.appending(path: "\(drops)", directoryHint: .isDirectory)
        // A folder left from an earlier launch holds someone else's drop; browsing would show it too.
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// Receives every promise at once and returns them and `files` in the drop's order.
    private static func receive(_ promised: [(index: Int, receiver: NSFilePromiseReceiver)], into folder: URL,
                                with files: [(index: Int, url: URL)]) async -> [URL] {
        let expected = promised.map { max($0.receiver.fileTypes.count, 1) }.reduce(0, +)
        return await withCheckedContinuation { continuation in
            let arrivals = Arrivals(files: files, expected: expected, continuation: continuation)
            for (index, receiver) in promised {
                // @Sendable: AppKit calls the reader on `queue`; a main-actor closure would trap there.
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { @Sendable url, error in
                    arrivals.add(index, error == nil ? url : nil)
                }
            }
        }
    }

    /// Collects promised files as they arrive, on the receive queue.
    private final class Arrivals: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [(index: Int, url: URL)]
        private var left: Int
        private let continuation: CheckedContinuation<[URL], Never>

        init(files: [(index: Int, url: URL)], expected: Int, continuation: CheckedContinuation<[URL], Never>) {
            self.files = files
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
