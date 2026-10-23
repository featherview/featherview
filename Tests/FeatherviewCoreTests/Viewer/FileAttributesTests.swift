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

    /// A prefetched read is shown again without another until something rewrites or touches the file.
    @Test func fileInfoIsCurrentUntilTheFileChanges() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 4)
        let info = FileInfo.read(url: url, page: 0)
        #expect(info.isCurrent)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: url.path)
        #expect(!info.isCurrent)
        let touched = FileInfo.read(url: url, page: 0)
        _ = try Fixtures.writeImage(to: url, width: 400, height: 300)
        try FileManager.default.setAttributes([.modificationDate: try #require(touched.modified)], ofItemAtPath: url.path)
        #expect(!touched.isCurrent)  // same date, other bytes
        let last = FileInfo.read(url: url, page: 0)
        try FileManager.default.removeItem(at: url)
        #expect(!last.isCurrent)
    }
}
