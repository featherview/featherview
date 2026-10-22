import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FileRenamerTests {
    private func names(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    private func touch(_ dir: URL, _ names: String...) throws {
        for name in names { try Data(name.utf8).write(to: dir.appendingPathComponent(name)) }
    }

    @Test func renamesAndKeepsContent() throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let bytes = try Data(contentsOf: a)
        let renamed = try FileRenamer.rename(a, to: "b.jpg", sidecars: [])
        #expect(renamed.lastPathComponent == "b.jpg")
        #expect(try names(in: dir) == ["b.jpg"])
        #expect(try Data(contentsOf: renamed) == bytes)
    }

    /// On a case-insensitive volume `IMG.jpg` already "exists": it is the same file, so it's no clash.
    @Test func caseOnlyRenameWorks() throws {
        let dir = try Fixtures.makeTempDir()
        let img = try Fixtures.writeImage(to: dir.appendingPathComponent("img.jpg"), width: 4, height: 4)
        let bytes = try Data(contentsOf: img)
        let renamed = try FileRenamer.rename(img, to: "IMG.jpg", sidecars: [])
        #expect(renamed.lastPathComponent == "IMG.jpg")
        #expect(try names(in: dir) == ["IMG.jpg"])
        #expect(try Data(contentsOf: renamed) == bytes)
    }

    @Test func takenNameChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        try touch(dir, "a.jpg", "b.jpg")
        #expect(throws: RenameProblem.taken("b.jpg")) {
            try FileRenamer.rename(dir.appendingPathComponent("a.jpg"), to: "b.jpg", sidecars: [])
        }
        #expect(try names(in: dir) == ["a.jpg", "b.jpg"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("a.jpg")) == Data("a.jpg".utf8))
        #expect(try Data(contentsOf: dir.appendingPathComponent("b.jpg")) == Data("b.jpg".utf8))
    }

    @Test func takenSidecarNameChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        try touch(dir, "IMG_1.jpg", "IMG_1.xmp", "B.xmp")
        #expect(throws: RenameProblem.taken("B.xmp")) {
            try FileRenamer.rename(dir.appendingPathComponent("IMG_1.jpg"), to: "B.jpg",
                                   sidecars: [dir.appendingPathComponent("IMG_1.xmp")])
        }
        #expect(try names(in: dir) == ["B.xmp", "IMG_1.jpg", "IMG_1.xmp"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("B.xmp")) == Data("B.xmp".utf8))
    }

    @Test func sidecarsFollowWithTheirExtension() throws {
        let dir = try Fixtures.makeTempDir()
        try touch(dir, "IMG_1.JPG", "IMG_1.xmp", "img_1.AAE")
        let renamed = try FileRenamer.rename(dir.appendingPathComponent("IMG_1.JPG"), to: "B.JPG",
                                             sidecars: [dir.appendingPathComponent("IMG_1.xmp"),
                                                        dir.appendingPathComponent("img_1.AAE")])
        #expect(renamed.lastPathComponent == "B.JPG")
        #expect(try names(in: dir) == ["B.AAE", "B.JPG", "B.xmp"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("B.AAE")) == Data("img_1.AAE".utf8))
    }

    @Test func unchangedNameDoesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        try touch(dir, "a.jpg")
        let a = dir.appendingPathComponent("a.jpg")
        #expect(try FileRenamer.rename(a, to: "a.jpg", sidecars: []) == a)
        #expect(try FileRenamer.rename(a, to: "  a.jpg ", sidecars: []) == a)
        #expect(try names(in: dir) == ["a.jpg"])
    }

    @Test func symlinkRenamesTheLink() throws {
        let dir = try Fixtures.makeTempDir()
        try touch(dir, "target.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("target.jpg"))
        let renamed = try FileRenamer.rename(link, to: "other.jpg", sidecars: [])
        #expect(try names(in: dir) == ["other.jpg", "target.jpg"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: renamed.path).hasSuffix("target.jpg"))
    }

    @Test func checkRejects() {
        #expect(FileRenamer.check("") == .empty)
        #expect(FileRenamer.check("  ") == .empty)
        #expect(FileRenamer.check("a/b") == .invalidCharacter)
        #expect(FileRenamer.check("a:b") == .invalidCharacter)
        #expect(FileRenamer.check("a\u{7}b") == .invalidCharacter)
        #expect(FileRenamer.check(".x") == .hidden)
        #expect(FileRenamer.check(String(repeating: "a", count: 256)) == .tooLong)
        #expect(FileRenamer.check(String(repeating: "a", count: 255)) == nil)
        #expect(FileRenamer.check("ü.jpg") == nil)
        #expect(FileRenamer.check("a b.jpg") == nil)
    }

    @Test func checkAcceptsFormatCharacters() {
        #expect(FileRenamer.check("👨\u{200D}👩\u{200D}👧.jpg") == nil)
        #expect(FileRenamer.check("می\u{200C}خواهم.jpg") == nil)
        #expect(FileRenamer.check("\u{200F}שלום.jpg") == nil)
        #expect(FileRenamer.check("soft\u{AD}hyphen.jpg") == nil)
        #expect(FileRenamer.check("a\u{7F}b") == .invalidCharacter)
    }

    @Test func stemRange() {
        #expect(FileRenamer.stemRange(of: "IMG_1.jpg") == NSRange(location: 0, length: 5))
        #expect(FileRenamer.stemRange(of: "a.tar.gz") == NSRange(location: 0, length: 5))
        #expect(FileRenamer.stemRange(of: ".hidden") == NSRange(location: 0, length: 7))
        #expect(FileRenamer.stemRange(of: "noext") == NSRange(location: 0, length: 5))
        #expect(FileRenamer.stemRange(of: "📷.jpg") == NSRange(location: 0, length: 2))
    }

    @Test func extensionChange() {
        let a = URL(filePath: "/tmp/a.jpg")
        #expect(FileRenamer.extensionChange(from: a, to: "b.JPG") == nil)
        #expect(FileRenamer.extensionChange(from: a, to: "a.png")! == ("jpg", "png"))
        #expect(FileRenamer.extensionChange(from: a, to: "a")! == ("jpg", ""))
    }

    /// The test bundle has no compiled catalog, so `String(localized:)` gives the English key.
    @Test func messagesUnderEnglish() {
        #expect(RenameProblem.empty.message == nil)
        #expect(RenameProblem.invalidCharacter.message == "A name can't contain “/” or “:”.")
        #expect(RenameProblem.hidden.message == "A name can't start with “.”: the file would be hidden.")
        #expect(RenameProblem.tooLong.message == "That name is too long.")
        #expect(RenameProblem.taken("B.jpg").message == "“B.jpg” is already taken. Choose a different name.")
    }
}
