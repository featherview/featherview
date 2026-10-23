import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FileAttributesTests {
    /// A symlink in the folder shows the image it points to: its bytes and date, not the link's own.
    private func linkToImage() throws -> (target: URL, link: URL) {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 64, height: 48)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
                                              ofItemAtPath: target.path)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return (target, link)
    }

    @Test func symlinkReportsItsTargetsSizeAndDate() throws {
        let (target, link) = try linkToImage()
        let bytes = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int
        #expect(target.fileSize == bytes)
        #expect(link.fileSize == bytes)
        #expect(target.modificationDate == Date(timeIntervalSince1970: 1_000_000_000))
        #expect(link.modificationDate == target.modificationDate)
    }

    @Test func missingFileHasNoSizeOrDate() throws {
        let missing = try Fixtures.makeTempDir().appendingPathComponent("gone.jpg")
        #expect(missing.fileSize == nil)
        #expect(missing.modificationDate == nil)
    }

    @Test func fileInfoOfASymlinkIsItsTargets() throws {
        let (target, link) = try linkToImage()
        let info = FileInfo.read(url: link, page: 0), own = FileInfo.read(url: target, page: 0)
        #expect(info.bytes == own.bytes)
        #expect(info.modified == own.modified)
        #expect(info.values["date"] == own.values["date"])
    }
}
