import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PhotosFetchTests {
    @Test func editedPictureKeepsItsOriginalName() {
        #expect(PhotosFetch.fileName(original: "IMG_1234.HEIC", written: "FullSizeRender.heic") == "IMG_1234.heic")
        #expect(PhotosFetch.fileName(original: "IMG_1234.HEIC", written: "FullSizeRender.jpeg") == "IMG_1234.jpeg")
        #expect(PhotosFetch.fileName(original: "IMG_1234.HEIC", written: "IMG_1234.HEIC") == "IMG_1234.HEIC")
        #expect(PhotosFetch.fileName(original: nil, written: "FullSizeRender.heic") == "FullSizeRender.heic")
    }

    @Test func aChangedPictureFetchesIntoANewFolder() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let first = PhotosFetch.folder(asset: "A/L0/001", modified: date)
        #expect(first == PhotosFetch.folder(asset: "A/L0/001", modified: date))
        #expect(first != PhotosFetch.folder(asset: "A/L0/001", modified: date.addingTimeInterval(1)))
        #expect(first != PhotosFetch.folder(asset: "B/L0/001", modified: date))
        #expect(first.deletingLastPathComponent().standardizedFileURL == BatchSettings.photosCache.standardizedFileURL)
    }

    @Test func aThumbnailKeepsTheFitPreviewInCloud() {
        let url = PhotosLocation.url(album: "library", asset: "A/L0/001")
        var inCloud: Set<URL> = []
        PhotosFetch.record(inCloud: true, url, target: .fit([PixelSize(width: 1000, height: 800)]), in: &inCloud)
        #expect(inCloud.contains(url))
        PhotosFetch.record(inCloud: false, url, target: .thumbnail(256), in: &inCloud)
        #expect(inCloud.contains(url))
        PhotosFetch.record(inCloud: false, url, target: .fit([PixelSize(width: 1000, height: 800)]), in: &inCloud)
        #expect(!inCloud.contains(url))
    }

    @Test func aSecondFetchFindsTheFileInPlace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("IMG_1.heic")
        let first = folder.appendingPathComponent(".a"), second = folder.appendingPathComponent(".b")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        #expect(PhotosFetch.moveIn(first, to: file))
        #expect(PhotosFetch.moveIn(second, to: file))  // the other caller won the race
        #expect(try Data(contentsOf: file) == Data("one".utf8))
        #expect(!PhotosFetch.moveIn(folder.appendingPathComponent(".gone"), to: folder.appendingPathComponent("x.heic")))
    }

    /// The launch-time emptying leaves alone the folders this run already uses: a drop being browsed and a
    /// library picture fetched for a batch. At quit everything goes.
    @Test func emptyingAtLaunchSkipsFoldersInUse() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "fv-caches-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
        let dropped = root.appending(path: "Dropped", directoryHint: .isDirectory)
        let folders = [photos.appending(path: "old"), photos.appending(path: "used"),
                       dropped.appending(path: "1"), dropped.appending(path: "2")]
        for folder in folders {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "IMG_0001.HEIC")
            try Data([1]).write(to: file)
            DropItem.noteReceived([file], in: folder)
        }
        PhotosFetch.use(folders[1])
        PhotosFetch.use(folders[2])
        PhotosFetch.emptyCaches(photos: photos, dropped: dropped, all: false)
        #expect(!fm.fileExists(atPath: folders[0].path))
        #expect(fm.fileExists(atPath: folders[1].appending(path: "IMG_0001.HEIC").path))
        #expect(fm.fileExists(atPath: folders[2].appending(path: "IMG_0001.HEIC").path))
        #expect(try fm.contentsOfDirectory(atPath: folders[3].path) == [])
        PhotosFetch.emptyCaches(photos: photos, dropped: dropped, all: true)
        #expect(!fm.fileExists(atPath: photos.path))
        #expect(try fm.contentsOfDirectory(atPath: folders[2].path) == [])
    }

    /// Spec "Photos library": each picture's iCloud note stays until its own original arrives, so going back to a
    /// picture still downloading shows it again, and one picture's failure never hides another's note.
    @Test func everyPictureKeepsItsOwnCloudNote() {
        let a = PhotosLocation.url(album: "library", asset: "A/L0/001")
        let b = PhotosLocation.url(album: "library", asset: "B/L0/001")
        var notes = PhotosCloudNotes()
        notes.started(a)
        notes.started(b)
        #expect(notes.isDownloading(a))
        #expect(notes.note(for: a) == PhotosText.downloading)
        notes.failed(a, name: "IMG_0001.HEIC")
        #expect(!notes.isDownloading(a))
        #expect(notes.note(for: a) == PhotosText.cantDownload(name: "IMG_0001.HEIC"))
        #expect(notes.note(for: b) == PhotosText.downloading)
        notes.arrived(b)
        #expect(notes.note(for: b) == nil)
        #expect(!notes.isDownloading(b))
        #expect(notes.note(for: nil) == nil)
    }

    /// Grid ⌘C puts copies on the clipboard that outlast quitting, which empties the fetch cache: each in a
    /// folder of its own, so two IMG_0001.HEIC never meet, and only the latest copy's files are kept.
    @Test func clipboardCopiesOutlastTheFetchCache() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "fv-clip-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
        let clipboard = root.appending(path: "Clipboard", directoryHint: .isDirectory)
        var fetched: [URL] = []
        for (index, folder) in ["a", "b"].enumerated() {
            let dir = photos.appending(path: folder, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: "IMG_0001.HEIC")
            try Data([UInt8(index)]).write(to: file)
            fetched.append(file)
        }
        let first = try #require(PhotosFetch.clipboardCopies(of: fetched, in: clipboard))
        #expect(first.map(\.lastPathComponent) == ["IMG_0001.HEIC", "IMG_0001.HEIC"])
        #expect(try first.map { try Data(contentsOf: $0) } == [Data([0]), Data([1])])
        PhotosFetch.emptyCaches(photos: photos, dropped: root.appending(path: "Dropped"), all: true)
        #expect(first.allSatisfy { fm.fileExists(atPath: $0.path) })
        let second = try #require(PhotosFetch.clipboardCopies(of: [], in: clipboard))
        #expect(second.isEmpty)
        #expect(!fm.fileExists(atPath: first[0].path))
        #expect(PhotosFetch.clipboardCopies(of: [photos.appending(path: "gone.heic")], in: clipboard) == nil)
    }
}
