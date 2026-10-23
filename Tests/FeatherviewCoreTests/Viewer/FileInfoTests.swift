import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FileInfoTests {
    /// A read for page 1 must not be taken for page 2 of the same file (status bar size and fit zoom %).
    @Test func infoIsForItsOwnPageOnly() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let info = FileInfo.read(url: tiff, page: 1)
        #expect(info.pixelSize == CGSize(width: 9, height: 4))  // the fixture's pages widen by one
        #expect(info.isFor(tiff, page: 1))
        #expect(!info.isFor(tiff, page: 2))
        #expect(!info.isFor(dir.appendingPathComponent("other.tif"), page: 1))
    }

    /// The overlay's `{size}` is the file's own pixels (fit mode shows a smaller decode), page 0's on any page.
    @Test func valuesAreTheFilesOwnPixelSizeAndDate() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 40, height: 30, orientation: 6)
        let info = FileInfo.read(url: url, page: 0)
        #expect(info.values["size"] == "30 × 40")
        #expect(info.values["date"] == info.modified?.formatted(date: .abbreviated, time: .shortened))
        #expect(info.values["date"]?.isEmpty == false)
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        #expect(FileInfo.read(url: tiff, page: 2).values["size"] == "8 × 4")
    }

    /// The viewer assigns a re-read only when it differs: each assignment redraws the status bar.
    @Test func readsCompareEqualUntilTheFileChanges() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 4)
        let first = FileInfo.read(url: url, page: 0)
        #expect(FileInfo.read(url: url, page: 0) == first)
        _ = try Fixtures.writeImage(to: url, width: 4, height: 8)  // a rotation rewrites it
        #expect(FileInfo.read(url: url, page: 0) != first)
    }

    /// After a rename the picture stays on screen: its info moves to the new URL without a read.
    @Test func movedKeepsValues() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 4)
        let info = FileInfo.read(url: a, page: 0)
        let b = dir.appendingPathComponent("b.jpg")  // never written: no read happens
        let moved = info.moved(to: b)
        #expect(moved.url == b)
        #expect(moved.page == info.page && moved.pixelSize == info.pixelSize)
        #expect(moved.bytes == info.bytes && moved.modified == info.modified && moved.values == info.values)
    }

    /// A swap with no read for the new file (prefetch cancelled, a file not prefetched, another page)
    /// must not leave the previous file's size, bytes, date and fit zoom % beside the new image.
    @Test func shownInfoIsNeverAnotherFilesOrPages() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 4)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 4, height: 8)
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let infoA = FileInfo.read(url: a, page: 0), infoB = FileInfo.read(url: b, page: 0)
        let page0 = FileInfo.read(url: tiff, page: 0), page1 = FileInfo.read(url: tiff, page: 1)

        #expect(FileInfo.shown(url: b, page: 0, known: infoB, current: infoA) == infoB)
        #expect(FileInfo.shown(url: b, page: 0, known: nil, current: infoA) == nil)
        #expect(FileInfo.shown(url: tiff, page: 1, known: nil, current: page0) == nil)
        // The same page decoded again (a zoom change) keeps its read.
        #expect(FileInfo.shown(url: tiff, page: 1, known: nil, current: page1) == page1)
        // A rotation drops page 0's read: the one on screen has the old size.
        #expect(FileInfo.shown(url: a, page: 0, known: nil, current: infoA) == nil)
    }
}
