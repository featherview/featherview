import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchInputListTests {
    private func image(_ dir: URL, _ name: String) throws -> URL {
        try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 4, height: 4)
    }

    private func names(_ items: [BatchInput]) -> [String] { items.map(\.url.lastPathComponent) }

    @Test func addAppendsInFinderOrder() throws {
        let dir = try Fixtures.makeTempDir()
        let first = try image(dir, "z.jpg")
        let img10 = try image(dir, "img10.jpg")
        let img2 = try image(dir, "img2.jpg")
        var list = BatchInputList([BatchInput(url: first)])
        list.add(files: [img10, img2])
        #expect(names(list.items) == ["z.jpg", "img2.jpg", "img10.jpg"])
        #expect(list.items.allSatisfy { $0.root == nil })
    }

    @Test func addSkipsDuplicatesAndSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try image(dir, "a.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        var list = BatchInputList()
        list.add(files: [a])
        list.add(files: [a, link])
        #expect(names(list.items) == ["a.jpg"])
        list.add(files: [try image(dir, "b.jpg"), dir.appendingPathComponent("b.jpg")])
        #expect(names(list.items) == ["a.jpg", "b.jpg"])
    }

    @Test func sizeOfKeepsTheSizeFromAddAndFollowsSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try image(dir, "a.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        let bytes = try #require(try a.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        var list = BatchInputList()
        list.add(files: [link])
        // Moved to the Trash by the run: the size from add still counts.
        try FileManager.default.removeItem(at: a)
        #expect(list.size(of: link) == bytes)
        #expect(list.size(of: dir.appendingPathComponent("other.jpg")) == 0)
    }

    @Test func addSkipsNonImages() throws {
        let dir = try Fixtures.makeTempDir()
        let text = dir.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: text)
        var list = BatchInputList()
        list.add(files: [text, try image(dir, "a.jpg")])
        #expect(names(list.items) == ["a.jpg"])
    }

    @Test func scanSkipsHiddenAndNonImages() throws {
        let dir = try Fixtures.makeTempDir()
        _ = try image(dir, "a.jpg")
        _ = try image(dir, ".hidden.jpg")
        try Data("hi".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let items = try BatchInputList.scan(folder: dir, subfolders: false)
        #expect(names(items) == ["a.jpg"])
    }

    @Test func scanWithSubfoldersIsDepthFirstInFinderOrder() throws {
        let dir = try Fixtures.makeTempDir()
        let fm = FileManager.default
        for sub in ["s10", "s2", "s2/deep", ".hid", "Pack.app"] {
            try fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        _ = try image(dir, "b.jpg")
        _ = try image(dir, "a.jpg")
        _ = try image(dir, "s10/x.jpg")
        _ = try image(dir, "s2/y.jpg")
        _ = try image(dir, "s2/deep/z.jpg")
        _ = try image(dir, ".hid/h.jpg")
        _ = try image(dir, "Pack.app/p.jpg")
        let flat = try BatchInputList.scan(folder: dir, subfolders: false)
        #expect(names(flat) == ["a.jpg", "b.jpg"])
        let deep = try BatchInputList.scan(folder: dir, subfolders: true)
        #expect(names(deep) == ["a.jpg", "b.jpg", "y.jpg", "z.jpg", "x.jpg"])
    }

    @Test func scanDoesNotFollowSymlinkLoops() throws {
        let dir = try Fixtures.makeTempDir()
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try image(sub, "a.jpg")
        try FileManager.default.createSymbolicLink(at: sub.appendingPathComponent("loop"), withDestinationURL: dir)
        let items = try BatchInputList.scan(folder: dir, subfolders: true)
        #expect(names(items) == ["a.jpg"])
    }

    @Test func droppedSymlinkedFolderIsScanned() throws {
        let dir = try Fixtures.makeTempDir()
        let real = dir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        _ = try image(real, "x.jpg")
        let file = try image(dir, "a.jpg")
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let dropped = BatchInputList.scan(dropped: [file, link])
        #expect(names(dropped.list.items) == ["a.jpg", "x.jpg"])
        #expect(dropped.list.items.last?.root == link)
        #expect(dropped.unreadable.isEmpty)
    }

    @Test func droppedPackageIsNotScanned() throws {
        // An app bundle or a Photos library is one item in Finder, never a folder of inputs.
        let dir = try Fixtures.makeTempDir()
        let package = dir.appendingPathComponent("Pictures.photoslibrary")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        _ = try image(package, "x.jpg")
        let file = try image(dir, "a.jpg")
        let dropped = BatchInputList.scan(dropped: [package, file])
        #expect(names(dropped.list.items) == ["a.jpg"])
        #expect(dropped.unreadable.isEmpty)
    }

    @Test func droppedUnreadableFolderIsReported() throws {
        let dir = try Fixtures.makeTempDir()
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        _ = try image(locked, "x.jpg")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let file = try image(dir, "a.jpg")
        let dropped = BatchInputList.scan(dropped: [locked, file])
        #expect(names(dropped.list.items) == ["a.jpg"])
        #expect(dropped.unreadable == [locked])
    }

    @Test func folderWithoutImagesIsReported() throws {
        // A camera card's DCIM holds only subfolders; an empty folder holds nothing.
        let dir = try Fixtures.makeTempDir()
        let empty = dir.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let dcim = dir.appendingPathComponent("DCIM/100APPLE")
        try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)
        _ = try image(dcim, "a.jpg")
        let dropped = BatchInputList.scan(dropped: [empty, dir.appendingPathComponent("DCIM")])
        #expect(names(dropped.list.items) == ["a.jpg"])
        #expect(dropped.empty == [empty])
        #expect(BatchInputList.notice(unreadable: [], empty: [empty]) == "No images in Empty")
        #expect(BatchInputList.notice(unreadable: [], empty: []) == nil)
        #expect(BatchInputList.notice(unreadable: [dcim], empty: [empty]) == "Can't open 100APPLE")
    }

    @Test func folderWhoseOnlyImagesSitInAnUnreadableSubfolderIsUnreadableNotEmpty() throws {
        let dir = try Fixtures.makeTempDir()
        let dcim = dir.appendingPathComponent("DCIM")
        let locked = dcim.appendingPathComponent("100APPLE")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        _ = try image(locked, "a.jpg")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let dropped = BatchInputList.scan(dropped: [dcim])
        #expect(dropped.unreadable.map(\.path) == [locked.path])
        #expect(dropped.empty.isEmpty)
        let chosen = BatchInputList.scanReporting(folder: dcim, subfolders: true)
        #expect(chosen.unreadable.map(\.path) == [locked.path])
        #expect(chosen.empty.isEmpty)
        #expect(BatchInputList.notice(unreadable: chosen.unreadable, empty: chosen.empty) == "Can't open 100APPLE")
    }

    @Test func convertTitleAgreesWithTheCount() {
        #expect(BatchInputList.convertTitle(count: 1) == "Convert 1 Image")
        #expect(BatchInputList.convertTitle(count: 48) == "Convert 48 Images")
    }

    /// "Recreate subfolders" takes each input's path below its root, so the chosen folder, even a
    /// symlink, is every item's root and prefixes its path.
    @Test func scanKeepsItemsUnderTheChosenFolderPath() throws {
        let dir = try Fixtures.makeTempDir()  // under /var, which is a symlink to /private/var
        let real = dir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("sub"), withIntermediateDirectories: true)
        _ = try image(real, "a.jpg")
        _ = try image(real, "sub/x.jpg")
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        for folder in [real, link] {
            let items = try BatchInputList.scan(folder: folder, subfolders: true)
            #expect(items.map(\.url.path).sorted() == [folder.path + "/a.jpg", folder.path + "/sub/x.jpg"])
            #expect(items.allSatisfy { $0.root == folder })
        }
    }

    @Test func addAndLoadSkipFoldersNamedLikeImages() throws {
        let dir = try Fixtures.makeTempDir()
        let folder = dir.appendingPathComponent("pics.jpg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var list = BatchInputList()
        list.add(files: [folder])
        #expect(list.items.isEmpty)
        #expect(list.load(listText: folder.path + "\n") == (0, 0))
        #expect(list.items.isEmpty)
    }

    @Test func namesDifferingOnlyInCaseAreTwoInputsOnCaseSensitiveVolumes() throws {
        let volume = try CaseSensitiveVolume()
        defer { volume.detach() }
        let upper = try image(volume.root, "A.jpg")
        let lower = try image(volume.root, "a.jpg")
        var list = BatchInputList()
        list.add(files: [upper, lower])
        #expect(list.items.count == 2)
        list.remove(at: IndexSet(list.items.indices.filter { list.items[$0].url == upper }))
        list.add(files: [upper])
        #expect(list.items.count == 2)
    }

    @Test func scanThrowsForMissingFolder() throws {
        let dir = try Fixtures.makeTempDir()
        #expect(throws: (any Error).self) {
            try BatchInputList.scan(folder: dir.appendingPathComponent("nope"), subfolders: true)
        }
    }

    private func list(_ names: [String]) -> BatchInputList {
        BatchInputList(names.map { BatchInput(url: URL(fileURLWithPath: "/tmp/\($0)")) })
    }

    @Test func appendDoesNotResolveItemsAlreadyInTheList() {
        // 20,000 rows: resolving every existing path per add took ~260 ms per call.
        var l = BatchInputList((0..<20_000).map { BatchInput(url: URL(fileURLWithPath: "/tmp/batch-perf/\($0).jpg")) })
        let start = ContinuousClock.now
        for i in 0..<20 { l.append([BatchInput(url: URL(fileURLWithPath: "/tmp/batch-perf/new\(i).jpg"))]) }
        #expect(ContinuousClock.now - start < .seconds(3))  // resolving every row again takes over 5 s
        #expect(l.items.count == 20_020)
        l.append([BatchInput(url: URL(fileURLWithPath: "/tmp/batch-perf/5.jpg"))])
        #expect(l.items.count == 20_020)
        l.remove(at: [5])
        l.append([BatchInput(url: URL(fileURLWithPath: "/tmp/batch-perf/5.jpg"))])
        #expect(l.items.count == 20_020)
        l.removeAll()
        l.append([BatchInput(url: URL(fileURLWithPath: "/tmp/batch-perf/5.jpg"))])
        #expect(l.items.count == 1)
    }

    /// The app builds the incoming list off the main thread; merging it must reuse its keys, not touch the disk again.
    @Test func appendingAListReusesItsKeys() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try image(dir, "a.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        let incoming = BatchInputList([BatchInput(url: link)])
        try FileManager.default.removeItem(at: link)  // resolving it now would give a different key
        var list = BatchInputList([BatchInput(url: a)])
        list.append(incoming)
        #expect(names(list.items) == ["a.jpg"])
        list.append(BatchInputList([BatchInput(url: dir.appendingPathComponent("b.jpg"))]))
        #expect(names(list.items) == ["a.jpg", "b.jpg"])
    }

    @Test func fileSizeFollowsSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 64, height: 64)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        let size = try #require(a.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(BatchInput(url: link).fileSize() == size)
        #expect(BatchInput(url: dir.appendingPathComponent("missing.jpg")).fileSize() == 0)
    }

    @Test func removeAndRemoveAll() {
        var l = list(["a", "b", "c", "d"])
        l.remove(at: [1, 3])
        #expect(names(l.items) == ["a", "c"])
        l.removeAll()
        #expect(l.items.isEmpty)
    }

    @Test func removeForgetsTheKeyStoredAtAddEvenAfterTheDiskChanged() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try image(dir, "a.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        var l = BatchInputList()
        l.add(files: [link])
        try FileManager.default.removeItem(at: link)  // the link's key now resolves differently
        l.remove(at: [0])
        #expect(l == BatchInputList())
        l.add(files: [a])
        #expect(names(l.items) == ["a.jpg"])
    }

    @Test func sortByNameIsFinderOrder() {
        var l = list(["img10.jpg", "B.jpg", "img2.jpg", "a.jpg"])
        l.sortByName()
        #expect(names(l.items) == ["a.jpg", "B.jpg", "img2.jpg", "img10.jpg"])
    }

    @Test func moveUpAndDownKeepsSelectionOrder() {
        var l = list(["a", "b", "c", "d", "e"])
        l.move([1, 3], by: -1)
        #expect(names(l.items) == ["b", "a", "d", "c", "e"])
        l.move([0, 2], by: 1)
        #expect(names(l.items) == ["a", "b", "c", "d", "e"])
        l.move([1, 2], by: 2)
        #expect(names(l.items) == ["a", "d", "e", "b", "c"])
    }

    @Test func moveClamps() {
        var l = list(["a", "b", "c", "d"])
        l.move([0, 2], by: -5)
        #expect(names(l.items) == ["a", "c", "b", "d"])
        l.move([2, 3], by: 1)
        #expect(names(l.items) == ["a", "c", "b", "d"])
        l.move([0], by: 10)
        #expect(names(l.items) == ["c", "b", "d", "a"])
    }

    @Test func listTextRoundTrips() throws {
        let dir = try Fixtures.makeTempDir()
        var l = BatchInputList()
        l.add(files: [try image(dir, "a.jpg"), try image(dir, "b.jpg")])
        let text = l.listText()
        #expect(text == l.items.map { $0.url.path + "\n" }.joined())
        var loaded = BatchInputList()
        let result = loaded.load(listText: text)
        #expect(result.added == 2 && result.missing == 0)
        #expect(loaded.items.map(\.url.path) == l.items.map(\.url.path))
    }

    @Test func loadSkipsMissingAndComments() throws {
        let dir = try Fixtures.makeTempDir()
        let b = try image(dir, "b.jpg")
        let a = try image(dir, "a.jpg")
        let text = """
        # saved list

        \(b.path)
        \(dir.appendingPathComponent("gone.jpg").path)
        \(a.path)
        \(dir.appendingPathComponent("gone2.png").path)
        """
        var l = BatchInputList()
        let result = l.load(listText: text)
        #expect(result.added == 2 && result.missing == 2)
        #expect(names(l.items) == ["b.jpg", "a.jpg"])  // saved order kept
    }

    @Test func loadHandlesCRLF() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try image(dir, "a.jpg")
        let b = try image(dir, "b.jpg")
        var l = BatchInputList()
        let result = l.load(listText: "\(a.path)\r\n\(b.path)\r\n")
        #expect(result.added == 2 && result.missing == 0)
        #expect(names(l.items) == ["a.jpg", "b.jpg"])
    }
}

@Suite struct BatchInputListBytesTests {
    @Test func totalBytesFollowsAddsAndRemoves() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8)
        let sizeA = BatchInput(url: a).fileSize(), sizeB = BatchInput(url: b).fileSize()
        var built = BatchInputList()
        built.add(files: [a, b])
        var list = BatchInputList()
        list.append(built)
        #expect(list.totalBytes == sizeA + sizeB)
        list.sortByName()
        list.move(IndexSet([0]), by: 1)
        #expect(list.totalBytes == sizeA + sizeB)
        list.remove(at: IndexSet([list.items.firstIndex { $0.url == a }!]))
        #expect(list.totalBytes == sizeB)
        list.removeAll()
        #expect(list.totalBytes == 0)
    }

    /// New Batch after a run that was stopped: converted rows go, failed and not-started rows stay.
    @Test func newBatchKeepsFailedAndUnstarted() throws {
        let dir = try Fixtures.makeTempDir()
        let urls = try ["a.jpg", "b.jpg", "c.jpg", "d.jpg"].map {
            try Fixtures.writeImage(to: dir.appendingPathComponent($0), width: 4, height: 4)
        }
        var list = BatchInputList()
        list.add(files: urls)
        let failed = urls[1], notStarted = urls[3]
        list.keep([notStarted, failed])
        #expect(list.items.map(\.url) == [failed, notStarted])
        #expect(list.totalBytes == BatchInput(url: failed).fileSize() + BatchInput(url: notStarted).fileSize())
        list.add(files: [urls[0], failed])  // a kept row is still a duplicate, a removed one adds again
        #expect(list.items.map(\.url) == [failed, notStarted, urls[0]])
    }
}
