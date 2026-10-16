import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FileInfoTests {
    /// A read for page 1 must not be taken for page 2 of the same file (status bar size and fit zoom %).
    @Test func infoIsForItsOwnPageOnly() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let info = FileInfo.read(url: tiff, page: 1)
        #expect(info.pixelSize == CGSize(width: 9, height: 4))  // the fixture's pages widen by one
        #expect(info.isFor(tiff, page: 1))
        #expect(!info.isFor(tiff, page: 2))
        #expect(!info.isFor(dir.appendingPathComponent("other.tif"), page: 1))
    }
}
