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
}
