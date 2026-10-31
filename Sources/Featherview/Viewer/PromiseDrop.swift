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
        guard !promised.isEmpty else { return Task { files.map(\.url) } }
        drops += 1
        let folder = BatchSettings.droppedCache.appending(path: "\(drops)", directoryHint: .isDirectory)
        return Task {
            // Emptying a leftover folder can take a while: off the main thread.
            guard let folder = await Task.detached(operation: { DropItem.freshFolder(folder) }).value else { return files.map(\.url) }
            let expected = promised.map { max($0.receiver.fileTypes.count, 1) }.reduce(0, +)
            // shortcut: a minute without an arrival ends the wait, a slower iCloud download is left out; upgrade if Photos reports progress.
            return await DropItem.collect(files, expected: expected, quiet: 60) { add in
                for (index, receiver) in promised {
                    receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { @Sendable url, error in
                        // @Sendable: AppKit calls the reader on `queue`; a main-actor closure would trap there.
                        add(index, error == nil ? url : nil)
                    }
                }
            }
        }
    }
}
