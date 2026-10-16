import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SidecarsTests {
    @Test func findsSidecarsOfAnyCase() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_1.JPG"), width: 4, height: 4)
        for name in ["IMG_1.xmp", "img_1.AAE", "IMG_1.thm", "IMG_10.xmp", "IMG_1.txt", "IMG_1.jpg.xmp"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        #expect(Sidecars.files(for: image).map(\.lastPathComponent) == ["IMG_1.thm", "IMG_1.xmp", "img_1.AAE"])
    }
}

@Suite struct FileMoverTests {
    @Test func movesIntoANewFolderWithSidecars() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let xmp = dir.appendingPathComponent("a.xmp")
        try Data("x".utf8).write(to: xmp)
        let dest = dir.appendingPathComponent("new/deeper")

        let moved = try FileMover.transfer(image, to: dest, operation: .move, sidecars: [xmp])
        #expect(moved.lastPathComponent == "a.jpg")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.xmp").path))
        #expect(!FileManager.default.fileExists(atPath: image.path))
        #expect(!FileManager.default.fileExists(atPath: xmp.path))
    }

    @Test func neverOverwritesAndKeepsSidecarsPaired() throws {
        let dir = try Fixtures.makeTempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let existing = try Fixtures.writeImage(to: dest.appendingPathComponent("a.jpg"), width: 9, height: 9)
        let before = try Data(contentsOf: existing)
        try Data("old".utf8).write(to: dest.appendingPathComponent("a 2.xmp"))  // " 2" is taken for the sidecar
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let xmp = dir.appendingPathComponent("a.xmp")
        try Data("new".utf8).write(to: xmp)

        let copied = try FileMover.transfer(image, to: dest, operation: .copy, sidecars: [xmp])
        #expect(copied.lastPathComponent == "a 3.jpg")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 3.xmp"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 2.xmp"), encoding: .utf8) == "old")
        #expect(try Data(contentsOf: existing) == before)
        #expect(FileManager.default.fileExists(atPath: image.path))  // a copy keeps the original
    }

    @Test func nameClashIgnoresCase() throws {
        let dir = try Fixtures.makeTempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Fixtures.writeImage(to: dest.appendingPathComponent("A.JPG"), width: 4, height: 4)
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dest, operation: .move).lastPathComponent == "a 2.jpg")
    }

    @Test func movingIntoItsOwnFolderChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dir, operation: .move) == image)
        #expect(try FolderScanner.images(around: dir).count == 1)
    }

    @Test func unwritableDestinationThrowsAndKeepsTheOriginal() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        #expect(throws: (any Error).self) { try FileMover.transfer(image, to: locked, operation: .move) }
        #expect(FileManager.default.fileExists(atPath: image.path))
    }
}
