import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PhotosLocationTests {
    @Test func roundTripsIdentifiersWithSlashes() {
        let url = PhotosLocation.url(album: "AB12/L0/040", asset: "6A1F-99/L0/001")
        #expect(PhotosLocation.album(of: url) == "AB12/L0/040")
        #expect(PhotosLocation.asset(of: url) == "6A1F-99/L0/001")
        #expect(url.deletingLastPathComponent() == PhotosLocation.albumURL("AB12/L0/040"))
        #expect(PhotosLocation.album(of: PhotosLocation.albumURL("AB12/L0/040")) == "AB12/L0/040")
        #expect(PhotosLocation.asset(of: PhotosLocation.albumURL("AB12/L0/040")) == nil)
    }

    @Test func anAlbumOpensAtTheKeptPictureElseAtItsEnd() {
        let urls = ["a/L0/001", "b/L0/001", "c/L0/001"].map { PhotosLocation.url(album: "library", asset: $0) }
        #expect(PhotosLocation.start(urls, kind: .library, keeping: urls[1]) == urls[1])
        #expect(PhotosLocation.start(urls, kind: .library, keeping: nil) == urls[2])
        #expect(PhotosLocation.start(urls, kind: .userAlbum, keeping: nil) == urls[0])
        // Deleted in Photos since: where the album opens anyway.
        let gone = PhotosLocation.url(album: "library", asset: "d/L0/001")
        #expect(PhotosLocation.start(urls, kind: .favorites, keeping: gone) == urls[0])
        #expect(PhotosLocation.start([], kind: .library, keeping: gone) == nil)
    }

    @Test func aFailedNameLookupIsKeptAndNotAskedAgain() {
        let a = PhotosLocation.url(album: "library", asset: "a/L0/001")
        let b = PhotosLocation.url(album: "library", asset: "b/L0/001")
        var names = PhotosNames()
        #expect(names.missing([a, b]) == [a, b])
        names.record("IMG_0001.HEIC", for: a)
        names.record(nil, for: b)
        #expect(names.missing([a, b]).isEmpty)
        #expect(names.lookup(a) == .found("IMG_0001.HEIC"))
        #expect(names.lookup(b) == .failed)
        #expect(names.lookup(PhotosLocation.url(album: "library", asset: "c/L0/001")) == .unknown)
        names.forgetFailures()
        #expect(names.missing([a, b]) == [b])
    }

    @Test func libraryURLsHaveNoFilePath() {
        let url = PhotosLocation.url(album: "library", asset: "X/L0/001")
        #expect(PhotosLocation.isLibrary(url) && !url.isFileURL)
        #expect(!PhotosLocation.isLibrary(URL(fileURLWithPath: "/tmp/featherview-photos/a.jpg")))
        #expect(PhotosLocation.asset(of: URL(fileURLWithPath: "/tmp/a.jpg")) == nil)
    }

    @Test func imageListKeepsTheCurrentLibraryPicture() {
        let urls = (1...3).map { PhotosLocation.url(album: "library", asset: "A\($0)/L0/001") }
        #expect(ImageList(urls: urls, current: urls[2]).index == 2)
    }

    @Test func sameNameDifferentAssets() {
        let a = PhotosLocation.url(album: "library", asset: "A/L0/001")
        let b = PhotosLocation.url(album: "library", asset: "B/L0/001")
        #expect(a != b && Set([a, b]).count == 2)
    }

    private func row(_ id: String, _ kind: PhotosAlbumKind, folders: [String] = []) -> PhotosAlbumRow {
        PhotosAlbumRow(id: id, name: id, folders: folders, kind: kind, count: nil)
    }

    @Test func sectionsInSheetOrder() {
        let user = row("Trip", .userAlbum), user2 = row("Cats", .userAlbum)
        let recents = row("Recents", .recents), selfies = row("Selfies", .mediaType)
        let library = row("library", .library), favorites = row("Favorites", .favorites)
        let sections = PhotosSheet.sections([user, recents, selfies, library, favorites, user2])
        #expect(sections == [
            .init(title: nil, rows: [library, favorites, recents]),
            .init(title: "Media Types", rows: [selfies]),
            .init(title: "My Albums", rows: [user, user2]),
        ])
        #expect(PhotosSheet.sections([user, library]) == [
            .init(title: nil, rows: [library]),
            .init(title: "My Albums", rows: [user]),
        ])
    }

    @Test func opensAtEnd() {
        #expect(PhotosAlbumKind.library.opensAtEnd && PhotosAlbumKind.recents.opensAtEnd
            && PhotosAlbumKind.mediaType.opensAtEnd && !PhotosAlbumKind.userAlbum.opensAtEnd
            && !PhotosAlbumKind.favorites.opensAtEnd)
    }

    @Test func subtitleJoinsFolders() {
        #expect(PhotosSheet.subtitle(row("A", .userAlbum, folders: ["Trips", "2025"])) == "Trips › 2025")
        #expect(PhotosSheet.subtitle(row("A", .userAlbum)) == nil)
    }

    @Test func textsNameTheirSubject() {
        #expect(PhotosText.cantDownload(name: "IMG_1234.HEIC") == "Can't download IMG_1234.HEIC from iCloud.")
        #expect(PhotosText.cantImport(format: "QOI") == "Photos can't import QOI.")
        #expect(PhotosText.cantAdd(name: "holiday.png") == "Can't add holiday.png to Photos.")
    }
}
