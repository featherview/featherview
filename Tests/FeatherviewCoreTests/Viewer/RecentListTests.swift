import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RecentListTests {
    let a = URL(fileURLWithPath: "/p/a.jpg"), b = URL(fileURLWithPath: "/p/b.jpg"), c = URL(fileURLWithPath: "/p/c.jpg")

    @Test func noteMovesTheFileFirst() {
        var list = RecentList()
        list.finishReload([a, b], token: list.startReload(), limit: 10)
        list.note(b, limit: 10)
        #expect(list.urls == [b, a])
    }

    /// ⌘O while the first reload still stats a sleeping disk: the reload's entries still arrive.
    @Test func aNoteDuringAReloadKeepsTheReloadsEntries() {
        var list = RecentList()
        let token = list.startReload()
        list.note(c, limit: 10)
        #expect(list.urls == [c])
        list.finishReload([a, b], token: token, limit: 10)
        #expect(list.urls == [c, a, b])
    }

    /// Clear Menu, then a file opened before the reload returns: only that file, not the cleared ones.
    @Test func aNoteAfterClearDoesNotBringClearedEntriesBack() {
        var list = RecentList()
        list.finishReload([a, b], token: list.startReload(), limit: 10)
        let token = list.startReload()  // after clearing the system's list
        list.note(c, limit: 10)
        list.finishReload([], token: token, limit: 10)
        #expect(list.urls == [c])
    }

    @Test func anOlderReloadIsDropped() {
        var list = RecentList()
        let old = list.startReload()
        let new = list.startReload()
        list.finishReload([a, b], token: new, limit: 10)
        list.finishReload([c], token: old, limit: 10)
        #expect(list.urls == [a, b])
    }

    @Test func keepsToTheLimit() {
        var list = RecentList()
        let token = list.startReload()
        list.note(c, limit: 2)
        list.finishReload([a, b], token: token, limit: 2)
        #expect(list.urls == [c, a])
    }

    /// The system's bookmark follows a trashed file into the Trash; it counts as gone.
    @Test func goneMeansMissingOrInTheTrash() throws {
        let dir = try Fixtures.makeTempDir()
        let kept = dir.appending(path: "a.jpg")
        let trash = dir.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let trashed = trash.appending(path: "b.jpg")
        try Data().write(to: kept)
        try Data().write(to: trashed)
        #expect(!RecentList.isGone(kept))
        #expect(RecentList.isGone(trashed))
        #expect(RecentList.isGone(dir.appending(path: "missing.jpg")))
    }

    /// A dropped notes.txt shows "Can't open" and isn't listed; images and folders are.
    @Test func onlyImagesAndFoldersAreRemembered() throws {
        let dir = try Fixtures.makeTempDir()
        let text = dir.appending(path: "notes.txt")
        try Data().write(to: text)
        #expect(RecentList.isRememberable(dir))
        #expect(RecentList.isRememberable(dir.appending(path: "a.jpg")))
        #expect(!RecentList.isRememberable(text))
        #expect(!RecentList.isRememberable(dir.appending(path: "archive.zip")))
    }
}
