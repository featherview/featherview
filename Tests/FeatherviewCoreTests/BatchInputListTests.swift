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

    @Test func scanThrowsForMissingFolder() throws {
        let dir = try Fixtures.makeTempDir()
        #expect(throws: (any Error).self) {
            try BatchInputList.scan(folder: dir.appendingPathComponent("nope"), subfolders: true)
        }
    }

    @Test func scanSetsRoot() throws {
        let dir = try Fixtures.makeTempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("s"), withIntermediateDirectories: true)
        _ = try image(dir, "a.jpg")
        _ = try image(dir, "s/b.jpg")
        let items = try BatchInputList.scan(folder: dir, subfolders: true)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.root == dir })
    }

    private func list(_ names: [String]) -> BatchInputList {
        BatchInputList(names.map { BatchInput(url: URL(fileURLWithPath: "/tmp/\($0)")) })
    }

    @Test func removeAndRemoveAll() {
        var l = list(["a", "b", "c", "d"])
        l.remove(at: [1, 3])
        #expect(names(l.items) == ["a", "c"])
        l.removeAll()
        #expect(l.items.isEmpty)
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
