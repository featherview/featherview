import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageListTests {
    let urls = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/x/\($0).jpg") }

    @Test func startsAtCurrent() {
        let list = ImageList(urls: urls, current: urls[2])
        #expect(list.index == 2)
        #expect(list.position == "3 / 4")
    }

    @Test func unknownCurrentStartsAtFirst() {
        #expect(ImageList(urls: urls, current: URL(fileURLWithPath: "/x/zzz.jpg")).index == 0)
    }

    @Test func matchesCurrentThroughSymlinksAndCase() throws {
        let dir = try Fixtures.makeTempDir()  // under /var, which is a symlink to /private/var
        let file = try Fixtures.writeImage(to: dir.appendingPathComponent("Photo.jpg"), width: 4, height: 4)
        let scanned = try FolderScanner.images(around: file)
        let list = ImageList(urls: scanned, current: URL(fileURLWithPath: dir.path + "/PHOTO.jpg"))
        #expect(list.current?.lastPathComponent == "Photo.jpg")
    }

    @Test func symlinkAndItsTargetStaySeparate() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("m.jpg"), width: 4, height: 4)
        for name in ["a-link.jpg", "z-link.jpg"] {
            try FileManager.default.createSymbolicLink(
                at: dir.appendingPathComponent(name), withDestinationURL: target)
        }
        let scanned = try FolderScanner.images(around: target)
        for name in ["a-link.jpg", "m.jpg", "z-link.jpg"] {
            let list = ImageList(urls: scanned, current: dir.appendingPathComponent(name))
            #expect(list.current?.lastPathComponent == name)
        }
    }

    @Test func namesDifferingOnlyInCaseStaySeparate() {
        let pair = ["IMG.jpg", "img.jpg"].map { URL(fileURLWithPath: "/x/\($0)") }
        #expect(ImageList(urls: pair, current: pair[1]).index == 1)
        #expect(ImageList(urls: pair, current: pair[0]).index == 0)
    }

    @Test func sameNameInOtherFolderIsNotCurrent() {
        #expect(ImageList(urls: urls, current: URL(fileURLWithPath: "/y/c.jpg")).index == 0)
    }

    @Test func navigationStopsAtTheEnds() {
        var list = ImageList(urls: urls, current: urls[2])
        // #expect can't call mutating methods, so each result is captured first.
        let movedToLast = list.next()
        #expect(movedToLast)
        #expect(list.index == 3)
        let movedPastEnd = list.next()
        #expect(!movedPastEnd)          // end of folder: caller shows the folder chooser
        #expect(list.index == 3)
        list.first()
        let movedBeforeStart = list.previous()
        #expect(!movedBeforeStart)
        #expect(list.index == 0)
        list.last()
        #expect(list.index == 3)
    }

    @Test func neighborsPutTheBrowsingDirectionFirstWithoutWrapping() {
        let list = ImageList(urls: urls, current: urls[1])
        #expect(list.neighbors(radius: 2, forward: true) == [urls[2], urls[3], urls[0]])
        #expect(list.neighbors(radius: 2, forward: false) == [urls[0], urls[2], urls[3]])
        #expect(list.neighbors(radius: 0, forward: true).isEmpty)
        // No wrapping at either end; a single image has no neighbours.
        #expect(ImageList(urls: urls, current: urls[3]).neighbors(radius: 2, forward: true) == [urls[2], urls[1]])
        #expect(ImageList(urls: [urls[0]]).neighbors(radius: 2, forward: true).isEmpty)
    }

    @Test func removeCurrentShowsFollowingImage() {
        var middle = ImageList(urls: urls, current: urls[1])
        middle.remove(urls[1])
        #expect(middle.current == urls[2])

        var last = ImageList(urls: urls, current: urls[3])
        last.remove(urls[3])
        #expect(last.current == urls[2])
        #expect(last.urls.count == 3)
    }

    @Test func removeByURLKeepsCurrentImage() {
        var list = ImageList(urls: urls, current: urls[2])
        list.remove(urls[0])  // before current: same image stays current
        #expect(list.current == urls[2])
        list.remove(urls[3])  // after current
        #expect(list.current == urls[2])
        list.remove(urls[2])  // current, now last: previous one takes over
        #expect(list.current == urls[1])
        list.remove(URL(fileURLWithPath: "/x/gone.jpg"))
        #expect(list.urls == [urls[1]])
    }

    @Test func removeSeveralAtOnce() {
        var list = ImageList(urls: urls, current: urls[2])
        list.remove(Set([urls[0], urls[3]]))  // around current: same image stays current
        #expect(list.urls == [urls[1], urls[2]])
        #expect(list.current == urls[2])
        var middle = ImageList(urls: urls, current: urls[1])
        middle.remove(Set([urls[1], urls[2]]))  // current goes: the next one left takes over
        #expect(middle.current == urls[3])
        var end = ImageList(urls: urls, current: urls[2])
        end.remove(Set([urls[2], urls[3], URL(fileURLWithPath: "/x/gone.jpg")]))  // none after: the last one left
        #expect(end.current == urls[1])
        var all = ImageList(urls: urls, current: urls[0])
        all.remove(Set(urls))
        #expect(all.isEmpty)
        #expect(all.current == nil)
    }

    @Test func emptyListIsSafe() {
        var list = ImageList(urls: [urls[0]])
        list.remove(urls[0])
        #expect(list.isEmpty)
        #expect(list.current == nil)
        #expect(list.position == "0 / 0")
        let movedNext = list.next()
        let movedPrevious = list.previous()
        #expect(!movedNext)
        #expect(!movedPrevious)
        list.remove(urls[0])
        #expect(list.current == nil)
    }

    @Test func heldRemovalStaysCurrentUntilTheNextKey() {
        var list = ImageList(urls: urls, current: urls[0])
        list.remove(urls[0], hold: true)
        // Actions on the current file must reach the one on screen, not the unseen next one.
        #expect(list.current == urls[0])
        #expect(list.isHolding)
        #expect(list.urls == Array(urls[1...]))
        #expect(list.neighbors(radius: 1, forward: true) == [urls[2]])
        let moved = list.next()
        #expect(moved)
        #expect(list.current == urls[1])
        #expect(!list.isHolding)
    }

    @Test func previousFromAHeldImageGoesToTheOneBefore() {
        var back = ImageList(urls: urls, current: urls[2])
        back.remove(urls[2], hold: true)
        back.previous()
        #expect(back.current == urls[1])
    }

    /// ← from a held first image is the start: it keeps holding, so ⌦ can't reach an unseen file.
    @Test func previousFromAHeldFirstImageKeepsHolding() {
        var start = ImageList(urls: urls, current: urls[0])
        start.remove(urls[0], hold: true)
        let movedBack = start.previous()
        #expect(!movedBack)
        #expect(start.current == urls[0])
        #expect(start.isHolding)
    }

    @Test func releaseMovesToTheImageAfterTheHeldOne() {
        var released = ImageList(urls: urls, current: urls[1])
        released.remove(urls[1], hold: true)
        released.release()
        #expect(released.current == urls[2])
    }

    /// A slideshow started on a held image plays on from the one after it.
    @Test func listedCurrentSkipsTheHeldImage() {
        var playing = ImageList(urls: urls, current: urls[1])
        #expect(playing.listedCurrent == urls[1])
        playing.remove(urls[1], hold: true)
        #expect(playing.listedCurrent == urls[2])
    }

    @Test func removingAnotherImageHoldsNothing() {
        var other = ImageList(urls: urls, current: urls[1])
        other.remove(urls[3], hold: true)
        #expect(!other.isHolding)
    }

    @Test func selectMakesCurrent() {
        var list = ImageList(urls: urls, current: urls[1])
        list.remove(urls[1], hold: true)
        let selected = list.select(urls[3])  // #expect can't call a mutating method
        #expect(selected)
        #expect(list.current == urls[3])
        #expect(!list.isHolding)
        #expect(list.position == "3 / 3")
    }

    @Test func selectUnknownIsFalse() {
        var list = ImageList(urls: urls, current: urls[1])
        let selected = list.select(URL(fileURLWithPath: "/x/zzz.jpg"))
        #expect(!selected)
        #expect(list == ImageList(urls: urls, current: urls[1]))
    }

    @Test func reorderKeepsCurrent() {
        let (a, b, c) = (urls[0], urls[1], urls[2])
        var list = ImageList(urls: [a, b, c], current: c)
        list.reorder([c, a, b])
        #expect(list.index == 0)
        #expect(list.current == c)
        #expect(!list.isHolding)
    }

    @Test func reorderKeepsHeldAndItsNext() {
        let (a, b, c) = (urls[0], urls[1], urls[2])
        var list = ImageList(urls: [a, b, c], current: b)
        list.remove(b, hold: true)
        list.reorder([c, a])
        #expect(list.isHolding)
        #expect(list.current == b)
        let moved = list.next()
        #expect(moved)
        #expect(list.current == c)
    }

    @Test func reorderMakesMissingCurrentHeld() {
        let (a, b, c) = (urls[0], urls[1], urls[2])
        var list = ImageList(urls: [a, b, c], current: b)
        list.reorder([a, c])
        #expect(list.isHolding)
        #expect(list.current == b)
        list.next()
        #expect(list.current == c)
    }

    @Test func reorderToEmpty() {
        var list = ImageList(urls: urls, current: urls[1])
        list.reorder([])
        #expect(list.urls.isEmpty)
        #expect(list.position == "0 / 0")
        #expect(list.current == urls[1])  // held on screen until the next key
        list.next()
        #expect(list.current == nil)
    }
}
