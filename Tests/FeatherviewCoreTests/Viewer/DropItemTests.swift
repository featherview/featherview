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

    /// A folder left from an earlier launch is emptied before a new drop lands in it.
    @Test func freshFolderEmptiesALeftoverFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fv-dropped-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appending(path: "old.heic"))
        #expect(DropItem.freshFolder(folder) == folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [])
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
