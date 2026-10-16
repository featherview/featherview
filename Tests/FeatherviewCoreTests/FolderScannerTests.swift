import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageFormatsTests {
    @Test(arguments: ["a.jpg", "a.JPG", "a.jpeg", "a.png", "a.heic", "a.tiff", "a.gif", "a.webp"])
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

    @Test func missingFolderThrows() {
        #expect(throws: (any Error).self) {
            try FolderScanner.images(around: URL(fileURLWithPath: "/no/such/folder/a.jpg"))
        }
    }
}
