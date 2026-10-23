import Foundation
import Testing
@testable import FeatherviewCore

/// root/ a/ (2 images)  b_empty/ (a text file)  c/ sub/  d2/  d10/  .hidden/  App.app/  link -> c  root1.jpg
private func makeTree() throws -> URL {
    let root = try Fixtures.makeTempDir()
    let manager = FileManager.default
    for folder in ["a", "b_empty", "c/sub", "d2", "d10", ".hidden", "App.app"] {
        try manager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    try Fixtures.writeImage(to: root.appendingPathComponent("a/a1.jpg"), width: 4, height: 4)
    try Fixtures.writeImage(to: root.appendingPathComponent("a/a2.png"), width: 4, height: 4, type: .png)
    try Data("x".utf8).write(to: root.appendingPathComponent("b_empty/x.txt"))
    try Fixtures.writeImage(to: root.appendingPathComponent("root1.jpg"), width: 4, height: 4)
    try manager.createSymbolicLink(at: root.appendingPathComponent("link"),
                                   withDestinationURL: root.appendingPathComponent("c"))
    return root
}

@Suite struct FolderTreeTests {
    @Test func subfoldersInFinderOrderSkippingHiddenAndPackages() throws {
        let root = try makeTree()
        #expect(FolderTree.subfolders(of: root).map(\.lastPathComponent) == ["a", "b_empty", "c", "d2", "d10", "link"])
        #expect(FolderTree.subfolders(of: root, includeHidden: true).map(\.lastPathComponent).first == ".hidden")
    }

    @Test func imageCounts() throws {
        let root = try makeTree()
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("a")) == 2)
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("b_empty")) == 0)
        #expect(FolderTree.imageCount(in: root) == 1)
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("missing")) == 0)
    }

    @Test func parentStopsAtRoot() throws {
        let root = try makeTree()
        #expect(FolderTree.parent(of: root.appendingPathComponent("a")).map(pathKey) == pathKey(root))
        #expect(FolderTree.parent(of: URL(fileURLWithPath: "/")) == nil)
    }
}

@Suite struct FolderChooserTests {
    @Test func startsOnTheFirstSubfolder() throws {
        let root = try makeTree()
        let chooser = FolderChooser(folder: root)
        #expect(chooser.entries.count == 8)  // again, parent, 6 subfolders
        #expect(chooser.entries[0] == .again(chooser.folder))
        guard case .parent = chooser.entries[1] else { Issue.record("no parent entry"); return }
        #expect(chooser.selected.url.lastPathComponent == "a")
    }

    @Test func withoutSubfoldersStartsOnTheParent() throws {
        let root = try makeTree()
        let chooser = FolderChooser(folder: root.appendingPathComponent("a"))
        #expect(chooser.entries.count == 2)
        #expect(pathKey(chooser.selected.url) == pathKey(root))
    }

    @Test func enterAndUpReturnToTheFolderWeCameFrom() throws {
        let root = try makeTree()
        var chooser = FolderChooser(folder: root)
        chooser.moveSelection(by: 2)  // a → c
        #expect(chooser.selected.url.lastPathComponent == "c")
        chooser.enter()
        #expect(chooser.folder.lastPathComponent == "c")
        #expect(chooser.selected.url.lastPathComponent == "sub")
        chooser.up()
        #expect(pathKey(chooser.folder) == pathKey(root))
        #expect(chooser.selected.url.lastPathComponent == "c")
    }

    @Test func enteringTheParentGoesUpAndAgainDoesNothing() throws {
        let root = try makeTree()
        var chooser = FolderChooser(folder: root.appendingPathComponent("d2"))
        chooser.moveSelection(by: -5)  // clamps at "again"
        chooser.enter()
        #expect(chooser.folder.lastPathComponent == "d2")
        chooser.moveSelection(by: 1)
        chooser.enter()
        #expect(pathKey(chooser.folder) == pathKey(root))
        #expect(chooser.selected.url.lastPathComponent == "d2")
        chooser.moveSelection(by: 99)
        #expect(chooser.selected.url.lastPathComponent == "link")
    }

    @Test func upFromASymlinkedFolderReturnsToTheLinksFolder() throws {
        // pics/link -> elsewhere/deep/photos (with a subfolder "x")
        let base = try Fixtures.makeTempDir()
        let pics = base.appendingPathComponent("pics"), photos = base.appendingPathComponent("elsewhere/deep/photos")
        try FileManager.default.createDirectory(at: photos.appendingPathComponent("x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pics, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: pics.appendingPathComponent("link"), withDestinationURL: photos)
        var chooser = FolderChooser(folder: pics)
        #expect(chooser.selected.url.lastPathComponent == "link")
        chooser.enter()
        chooser.enter()  // into x, below the link
        chooser.up()
        #expect(chooser.folder.lastPathComponent == "link")
        chooser.up()
        #expect(pathKey(chooser.folder) == pathKey(pics))
        #expect(chooser.selected.url.lastPathComponent == "link")
    }

    @Test func upFromALinkToASiblingReturnsToTheLink() throws {
        let root = try makeTree()  // link -> c, both in root
        var chooser = FolderChooser(folder: root)
        chooser.moveSelection(by: 5)  // a → link
        #expect(chooser.selected.url.lastPathComponent == "link")
        chooser.enter()
        chooser.up()
        #expect(chooser.selected.url.lastPathComponent == "link")
    }

    @Test func upTellsFoldersApartThatDifferOnlyInCase() throws {
        let volume = try CaseSensitiveVolume()
        defer { volume.detach() }
        let base = volume.root
        for name in ["Photos", "photos"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let names = FolderChooser(folder: base).entries.map(\.url.lastPathComponent)
        for name in ["Photos", "photos"] {
            var chooser = FolderChooser(folder: base)
            chooser.moveSelection(by: try #require(names.firstIndex(of: name)) - chooser.selection)
            chooser.enter()
            chooser.up()
            #expect(chooser.selected.url.lastPathComponent == name)
        }
    }

    @Test func rootHasNoParentEntry() {
        var chooser = FolderChooser(folder: URL(fileURLWithPath: "/"))
        #expect(!chooser.entries.contains { if case .parent = $0 { true } else { false } })
        chooser.up()
        #expect(chooser.folder.path == "/")
    }
}
