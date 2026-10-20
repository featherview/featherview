import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageFormatsTests {
    @Test(arguments: ["a.jpg", "a.JPG", "a.jpeg", "a.png", "a.heic", "a.tiff", "a.gif", "a.webp", "a.jfif", "a.JFIF", "a.jif", "a.jfi", "a.pdf", "a.PDF", "a.pam", "a.PAM", "a.pfm"])
    func decodable(_ name: String) {
        #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
    }

    @Test(arguments: ["a.txt", "a", "a.mov"])
    func notDecodable(_ name: String) {
        #expect(!ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
    }

    /// PAM (Netpbm P7) has no UTType on macOS, ImageIO reads it by content, alpha included.
    @Test func pamDecodesWithAlpha() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.pam")
        let header = "P7\nWIDTH 2\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n"
        try (Data(header.utf8) + Data([255, 0, 0, 255, 0, 255, 0, 0])).write(to: url)
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0].a == 0)
    }
}

@Suite struct FolderScannerTests {
    @Test func listsImagesInFinderOrderSkippingOtherAndHiddenFiles() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("img10.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent("img2.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent("img1.png"), width: 4, height: 4, type: .png)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.jpg"))

        let fromFile = try FolderScanner.images(around: dir.appendingPathComponent("img2.jpg"))
        #expect(fromFile.map(\.lastPathComponent) == ["img1.png", "img2.jpg", "img10.jpg"])
        #expect(try FolderScanner.images(around: dir).count == 3)
    }

    // The scanner asks once per extension; case must not mix up a type with another.
    @Test func extensionsInAnyCaseAreJudgedAlike() throws {
        let dir = try Fixtures.makeTempDir()
        for name in ["B.JPG", "a.jpg", "c.TXT", "d.txt", "e.Png"] {
            try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 4, height: 4)
        }
        #expect(try FolderScanner.images(around: dir).map(\.lastPathComponent) == ["a.jpg", "B.JPG", "e.Png"])
    }

    // Opening a folder decodes its first image before the rest is sorted.
    @Test func firstImageWithoutSortingMatchesTheSortedList() throws {
        let dir = try Fixtures.makeTempDir()
        for name in ["img10.jpg", "Img2.jpg", "img1b.jpg", "img1.jpg"] {
            try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 4, height: 4)
        }
        let unsorted = try FolderScanner.images(around: dir, sorted: false)
        let sorted = FolderScanner.inFinderOrder(unsorted)
        #expect(sorted == (try FolderScanner.images(around: dir)))
        #expect(sorted.map(\.lastPathComponent) == ["img1.jpg", "img1b.jpg", "Img2.jpg", "img10.jpg"])
        #expect(FolderScanner.firstInFinderOrder(unsorted) == sorted.first)
        #expect(FolderScanner.firstInFinderOrder([]) == nil)
    }

    @Test func followsSymlinkToFolder() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try Fixtures.writeImage(to: sub.appendingPathComponent("s.jpg"), width: 4, height: 4)
        let link = dir.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sub)

        #expect(try FolderScanner.images(around: link).map(\.lastPathComponent) == ["s.jpg"])
    }

    @Test func skipsFoldersAndBrokenLinksButKeepsLinkedImages() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Folder.jpg"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("broken.jpg"),
            withDestinationURL: dir.appendingPathComponent("gone.jpg"))
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("b.jpg"), withDestinationURL: dir.appendingPathComponent("a.jpg"))

        #expect(try FolderScanner.images(around: dir).map(\.lastPathComponent) == ["a.jpg", "b.jpg"])
    }

    @Test(arguments: [".hidden.jpg", "x", "photo.raw-ish"])
    func alwaysListsTheOpenedFile(_ name: String) throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 4, height: 4)

        let names = try FolderScanner.images(around: dir.appendingPathComponent(name)).map(\.lastPathComponent)
        #expect(names.sorted() == ["a.jpg", name].sorted())
    }

    @Test func openedFileInOtherCaseIsListedOnce() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("img.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent("b.png"), width: 4, height: 4)

        let names = try FolderScanner.images(around: dir.appendingPathComponent("IMG.JPG")).map(\.lastPathComponent)
        #expect(names == ["b.png", "img.jpg"])
    }

    @Test func unlistableFolderStillOpensTheFile() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        try FileManager.default.setAttributes([.posixPermissions: 0o311], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        #expect(try FolderScanner.images(around: url).map(\.lastPathComponent) == ["a.jpg"])
        #expect(throws: (any Error).self) { try FolderScanner.images(around: dir) }
    }

    @Test func missingFolderThrows() {
        #expect(throws: (any Error).self) {
            try FolderScanner.images(around: URL(fileURLWithPath: "/no/such/folder/a.jpg"))
        }
    }
}

@Suite struct HiddenFilesTests {
    @Test func hiddenFilesAreListedWhenAsked() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent(".b.jpg"), width: 4, height: 4)
        #expect(try FolderScanner.images(around: dir).map(\.lastPathComponent) == ["a.jpg"])
        #expect(try FolderScanner.images(around: dir, includeHidden: true).map(\.lastPathComponent) == [".b.jpg", "a.jpg"])
    }
}
