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

    @Test func sidecarsGoWithAnImageEvenWhenAnotherSharesTheName() throws {
        let dir = try Fixtures.makeTempDir()
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_1.JPG"), width: 4, height: 4)
        for name in ["IMG_1.CR2", "IMG_1.xmp"] { try Data("x".utf8).write(to: dir.appendingPathComponent(name)) }
        #expect(Sidecars.files(for: jpeg).map(\.lastPathComponent) == ["IMG_1.xmp"])  // spec: no RAW+JPEG exception
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

    @Test func danglingLinkAtTheTargetNameCountsAsTaken() throws {
        let dir = try Fixtures.makeTempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dest.appendingPathComponent("a.jpg").path,
                                                   withDestinationPath: "nowhere.jpg")
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dest, operation: .move).lastPathComponent == "a 2.jpg")
    }

    @Test func linkedImageArrivesAsTheImageNotAsALink() throws {
        for operation in [FileOperation.copy, .move] {
            let dir = try Fixtures.makeTempDir()
            let real = try Fixtures.writeImage(to: dir.appendingPathComponent("real.jpg"), width: 4, height: 4)
            let link = dir.appendingPathComponent("a.jpg")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "real.jpg")

            let placed = try FileMover.transfer(link, to: dir.appendingPathComponent("dest"), operation: operation)
            #expect(try Data(contentsOf: placed) == Data(contentsOf: real))
            #expect(try placed.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
            #expect(FileManager.default.fileExists(atPath: real.path))  // the linked-to file is never touched
            let linkKept = (try? FileManager.default.attributesOfItem(atPath: link.path)) != nil
            #expect(linkKept == (operation == .copy))
        }
    }

    @Test func movingIntoItsOwnFolderChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dir, operation: .move) == image)
        #expect(try FolderScanner.images(around: dir).count == 1)
    }

    @Test func movingIntoItsOwnFolderThroughALinkChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        let pics = dir.appendingPathComponent("pics")
        try FileManager.default.createDirectory(at: pics, withIntermediateDirectories: true)
        let linked = dir.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(atPath: linked.path, withDestinationPath: "pics")
        let image = try Fixtures.writeImage(to: pics.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let xmp = pics.appendingPathComponent("a.xmp")
        try Data("x".utf8).write(to: xmp)

        #expect(try FileMover.transfer(image, to: linked, operation: .move, sidecars: [xmp]) == image)
        let viaLink = linked.appendingPathComponent("a.jpg")
        #expect(try FileMover.transfer(viaLink, to: pics, operation: .move) == viaLink)
        #expect(try FileManager.default.contentsOfDirectory(atPath: pics.path).sorted() == ["a.jpg", "a.xmp"])
    }

    @Test func linkThatCannotBeRemovedLeavesNoCopyBehind() throws {
        let dir = try Fixtures.makeTempDir()
        let real = try Fixtures.writeImage(to: dir.appendingPathComponent("real.jpg"), width: 4, height: 4)
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let link = locked.appendingPathComponent("a.jpg")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let dest = dir.appendingPathComponent("dest")

        #expect(throws: (any Error).self) { try FileMover.transfer(link, to: dest, operation: .move) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
        #expect((try? FileManager.default.attributesOfItem(atPath: link.path)) != nil)
    }

    @Test func folderDifferingOnlyInCaseIsAnotherFolderOnCaseSensitiveVolumes() throws {
        let volume = try CaseSensitiveVolume()
        defer { volume.detach() }
        let pics = volume.root.appendingPathComponent("Pics")
        try FileManager.default.createDirectory(at: pics, withIntermediateDirectories: true)
        let image = try Fixtures.writeImage(to: pics.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let lower = volume.root.appendingPathComponent("pics")

        let moved = try FileMover.transfer(image, to: lower, operation: .move)
        #expect(moved.path == lower.appendingPathComponent("a.jpg").path)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: image.path))
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

/// A small case-sensitive APFS disk image, mounted privately for one test.
private struct CaseSensitiveVolume {
    let image: URL
    let root: URL

    init() throws {
        let dir = try Fixtures.makeTempDir()
        image = dir.appendingPathComponent("cs.dmg")
        root = dir.appendingPathComponent("mnt")
        try Self.hdiutil(["create", "-size", "8m", "-fs", "Case-sensitive APFS", "-volname", "FVTest", image.path])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.hdiutil(["attach", "-nobrowse", "-mountpoint", root.path, image.path])
    }

    func detach() { try? Self.hdiutil(["detach", "-force", root.path]) }

    private static func hdiutil(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
