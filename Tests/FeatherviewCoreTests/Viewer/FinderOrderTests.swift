import Foundation
import Testing
@testable import FeatherviewCore

/// The viewer's list, the folder chooser and the batch's Sort by Name put names in one order.
@Suite struct FinderOrderTests {
    /// Names Finder's compare alone may call equal: case, zero-padded numbers, composed and decomposed é.
    static let names = ["file01.jpg", "a.jpg", "file1.jpg", "A.jpg", "b10.jpg", "\u{E9}.jpg", "b9.jpg", "e\u{301}.jpg",
                        "Photos 2", "photos 10"]

    @Test func everyTwoNamesHaveOneOrder() {
        for a in Self.names {
            for b in Self.names where a.unicodeScalars.elementsEqual(b.unicodeScalars) == false {
                #expect(FolderScanner.finderPrecedes(a, b) != FolderScanner.finderPrecedes(b, a), "\(a) vs \(b)")
            }
        }
    }

    @Test func orderDoesNotDependOnTheInput() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let urls = Self.names.map { folder.appendingPathComponent($0) }
        let order = FolderScanner.inFinderOrder(urls)
        #expect(FolderScanner.inFinderOrder(urls.reversed()) == order)
        #expect(FolderScanner.firstInFinderOrder(urls.reversed()) == order.first)
        #expect(Array(order.prefix(2).map(\.lastPathComponent)) == ["a.jpg", "A.jpg"])
    }

    @Test func batchSortsByNameAsTheViewerLists() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let urls = Self.names.map { folder.appendingPathComponent($0) }
        var list = BatchInputList(urls.reversed().map { BatchInput(url: $0) })
        list.sortByName()
        // The list keeps one of names that are one file on a case-insensitive volume.
        #expect(list.items.count >= 6)
        #expect(list.items.map(\.url) == FolderScanner.inFinderOrder(list.items.map(\.url).reversed()))
    }

    /// Folders on disk can't differ only by case or normalization (APFS default), so these differ otherwise.
    @Test func folderChooserListsAsTheViewer() throws {
        let dir = try Fixtures.makeTempDir()
        let names = ["file01", "file1", "b10", "b9", "Photos 2", "photos 10"]
        for name in names { try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: false) }
        let viewer = FolderScanner.inFinderOrder(names.map { dir.appendingPathComponent($0) }).map(\.lastPathComponent)
        #expect(FolderTree.subfolders(of: dir).map(\.lastPathComponent) == viewer)
    }
}
