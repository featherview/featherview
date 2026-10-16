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

    @Test func neighborsNearestFirstWithoutWrapping() {
        let list = ImageList(urls: urls, current: urls[1])
        #expect(list.neighbors(radius: 2) == [urls[2], urls[0], urls[3]])
        #expect(ImageList(urls: urls, current: urls[3]).neighbors(radius: 2) == [urls[2], urls[1]])
        #expect(list.neighbors(radius: 0).isEmpty)
        #expect(ImageList(urls: [urls[0]]).neighbors(radius: 2).isEmpty)
    }

    @Test func removeCurrentShowsFollowingImage() {
        var middle = ImageList(urls: urls, current: urls[1])
        middle.removeCurrent()
        #expect(middle.current == urls[2])

        var last = ImageList(urls: urls, current: urls[3])
        last.removeCurrent()
        #expect(last.current == urls[2])
        #expect(last.urls.count == 3)
    }

    @Test func emptyListIsSafe() {
        var list = ImageList(urls: [urls[0]])
        list.removeCurrent()
        #expect(list.isEmpty)
        #expect(list.current == nil)
        #expect(list.position == "0 / 0")
        let movedNext = list.next()
        let movedPrevious = list.previous()
        #expect(!movedNext)
        #expect(!movedPrevious)
        list.removeCurrent()
        #expect(list.current == nil)
    }
}
