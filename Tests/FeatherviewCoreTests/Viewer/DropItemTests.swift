import FeatherviewCore
import Foundation
import Testing

struct DropItemTests {
    private let file = "public.file-url"
    private let promises: Set<String> = ["com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.promised-file-url"]

    /// A promise is received only for an item without a file URL; the receivers count every promise item.
    @Test func promisesOnlyForItemsWithoutAFileURL() {
        let items = [
            ["com.apple.pasteboard.promised-file-url"],
            [file, "com.apple.pasteboard.promised-file-url"],
            [file],
            ["public.utf8-plain-text"],
            ["com.apple.NSFilePromiseItemMetaData"],
        ]
        #expect(DropItem.plan(items, fileURLType: file, promiseTypes: promises)
                == [.promise(0), .file, .file, .skipped, .promise(2)])
    }

    /// A folder left from an earlier launch is emptied before a new drop lands in it: the files the drop
    /// received are deleted, anything else (a file the user saved or changed there) goes to the Trash.
    @Test func freshFolderDeletesOnlyReceivedFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "fv-dropped-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let folder = root.appending(path: "1", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let received = folder.appending(path: "old.heic"), changed = folder.appending(path: "changed.heic")
        try Data([1]).write(to: received)
        try Data([1]).write(to: changed)
        DropItem.noteReceived([received, changed, URL(filePath: "/elsewhere/finder.jpg")], in: folder)
        try Data([2]).write(to: changed)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: changed.path)
        let saved = folder.appending(path: "saved.png")
        try Data([3]).write(to: saved)
        var trashed: [String] = []
        #expect(DropItem.freshFolder(folder) { trashed.append($0.lastPathComponent); try? fm.removeItem(at: $0) } == folder)
        #expect(try fm.contentsOfDirectory(atPath: folder.path) == [])
        #expect(trashed.sorted() == ["changed.heic", "saved.png"])
    }

    /// Save As never starts in a drop's folder, which a later launch empties.
    @Test func saveFolderLeavesDropFolders() {
        let pictures = URL(filePath: "/Users/someone/Pictures", directoryHint: .isDirectory)
        let card = URL(filePath: "/Volumes/Card/DCIM", directoryHint: .isDirectory)
        #expect(DropItem.saveFolder(BatchSettings.droppedCache.appending(path: "3", directoryHint: .isDirectory), else: pictures) == pictures)
        #expect(DropItem.saveFolder(card, else: pictures) == card)
        #expect(DropItem.saveFolder(nil, else: pictures) == pictures)
    }

    /// All promises arrived: the files come back in the drop's order, with the file URLs between them.
    @Test func arrivalsKeepTheDropOrder() async {
        let urls = await DropItem.collect([(1, URL(filePath: "/a/finder.jpg"))], expected: 2, quiet: 5) { add in
            add(2, URL(filePath: "/d/second.heic"))
            add(0, URL(filePath: "/d/first.heic"))
        }
        #expect(urls.map(\.lastPathComponent) == ["first.heic", "finder.jpg", "second.heic"])
    }

    /// A promise whose reader is never called doesn't keep the drop waiting: after `quiet` seconds without an
    /// arrival, what arrived comes back.
    @Test func arrivalsStopWaitingWhenAPromiseNeverArrives() async {
        let urls = await DropItem.collect([], expected: 3, quiet: 0.2) { add in
            add(0, URL(filePath: "/d/first.heic"))
            add(1, nil)
        }
        #expect(urls.map(\.lastPathComponent) == ["first.heic"])
    }
}
