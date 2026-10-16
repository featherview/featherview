import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageFormatsTests {
    @Test(arguments: ["a.jpg", "a.JPG", "a.jpeg", "a.png", "a.heic", "a.tiff", "a.gif", "a.webp", "a.jfif", "a.JFIF", "a.jif", "a.jfi"])
    func decodable(_ name: String) {
        #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
    }

    @Test(arguments: ["a.txt", "a.pdf", "a", "a.mov"])
    func notDecodable(_ name: String) {
        #expect(!ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
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
        #expect(Set(names) == ["a.jpg", name])
    }

    @Test func missingFolderThrows() {
        #expect(throws: (any Error).self) {
            try FolderScanner.images(around: URL(fileURLWithPath: "/no/such/folder/a.jpg"))
        }
    }
}
