import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct OrientationRotatorTests {
    @Test(arguments: 1...8)
    func fourTurnsAreIdentity(_ orientation: Int) {
        var value = orientation
        for _ in 0..<4 { value = OrientationRotator.next(value, .clockwise) }
        #expect(value == orientation)
        let turned = OrientationRotator.next(orientation, .clockwise)
        #expect(OrientationRotator.next(turned, .counterClockwise) == orientation)
    }

    @Test func rotatesJPEGWithoutReencoding() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 60, height: 30)
        let sizeBefore = try Data(contentsOf: url).count

        try OrientationRotator.rotate(url, .clockwise)

        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 30, height: 60))
        #expect(abs(try Data(contentsOf: url).count - sizeBefore) < 200)  // re-encoding would change it a lot
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(".featherview-") }
        #expect(leftovers.isEmpty)
    }

    @Test func refusesFormatsWithoutReliableOrientation() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("p.png"), width: 4, height: 4, type: .png)
        #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.rotate(url, .clockwise) }
    }

    @Test func readOnlyFolderLeavesOriginalIntact() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("ro.jpg"), width: 10, height: 5)
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        #expect(throws: RotateError.writeFailed) { try OrientationRotator.rotate(url, .clockwise) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func rotatesThroughSymlink() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("target.jpg"), width: 60, height: 30)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try OrientationRotator.rotate(link, .clockwise)

        #expect(ImageDecoder.displaySize(of: target) == CGSize(width: 30, height: 60))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func refusesPNGWithJPEGExtension() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("png.jpg"), width: 4, height: 4, type: .png)
        let original = try Data(contentsOf: url)
        #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.rotate(url, .clockwise) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func refusesPagesAfterTheFirstAndLeavesTheFileUntouched() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let original = try Data(contentsOf: url)

        // Turning a later page means re-encoding every page (lossy for JPEG-compressed TIFFs).
        #expect(throws: RotateError.notFirstPage) { try OrientationRotator.rotate(url, .clockwise, page: 1) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func rotatingTheFirstPageKeepsTheOtherPages() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)

        try OrientationRotator.rotate(url, .clockwise)

        #expect(ImageDecoder.pageCount(of: url) == 3)
        #expect(ImageDecoder.displaySize(of: url, page: 0) == CGSize(width: 4, height: 8))
        #expect(ImageDecoder.displaySize(of: url, page: 2) == CGSize(width: 10, height: 4))
    }

    @Test(arguments: 1...8)
    func flipTablesMatchMirroring(_ orientation: Int) {
        let next: (Int, OrientationChange) -> Int = OrientationRotator.next
        #expect(next(next(orientation, .flip(.horizontal)), .flip(.horizontal)) == orientation)
        #expect(next(next(orientation, .flip(.vertical)), .flip(.vertical)) == orientation)
        #expect(next(next(orientation, .flip(.horizontal)), .flip(.vertical))
            == next(next(orientation, .rotate(.clockwise)), .rotate(.clockwise)))
    }

    /// "ab/cd" mirrored left–right is "ba/dc", top–bottom "cd/ab".
    static func mirrored(_ corners: String, _ flip: Flip) -> String {
        let c = Array(corners)
        return switch flip {
        case .horizontal: String([c[1], c[0], "/", c[4], c[3]])
        case .vertical: String([c[3], c[4], "/", c[0], c[1]])
        }
    }

    @Test(arguments: [UTType.jpeg, .tiff, .heic], 1...8)
    func flipsEveryOrientationLosslessly(_ type: UTType, _ orientation: Int) throws {
        for flip in [Flip.horizontal, .vertical] {
            let dir = try Fixtures.makeTempDir()
            let url = try Fixtures.writeQuadrants(
                to: dir.appendingPathComponent("q.\(type.preferredFilenameExtension!)"), type: type,
                orientation: orientation)
            let before = Fixtures.corners(of: url)
            let sizeBefore = try Data(contentsOf: url).count
            #expect(before.count == 5 && !before.contains("?"), "\(before)")

            try OrientationRotator.apply(url, .flip(flip))

            #expect(Fixtures.corners(of: url) == Self.mirrored(before, flip))
            // ImageIO re-packs an uncompressed TIFF's strips (lossless, a few KB larger), so only the
            // compressed formats show a re-encode by size.
            if type != .tiff { #expect(abs(try Data(contentsOf: url).count - sizeBefore) < 200) }
        }
    }

    @Test func flipRefusesWhatRotateRefuses() throws {
        let dir = try Fixtures.makeTempDir()
        let files = [
            try Fixtures.writeImage(to: dir.appendingPathComponent("p.png"), width: 4, height: 4, type: .png),
            try Fixtures.writeImage(to: dir.appendingPathComponent("png.jpg"), width: 4, height: 4, type: .png),
            try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1]),
            try Fixtures.writeHEICS(to: dir.appendingPathComponent("s.heics"), delays: [0.1, 0.1]),
        ]
        for url in files {
            let original = try Data(contentsOf: url)
            #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.apply(url, .flip(.horizontal)) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func flipRefusesLaterTIFFPages() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let original = try Data(contentsOf: url)
        #expect(throws: RotateError.notFirstPage) { try OrientationRotator.apply(url, .flip(.vertical), page: 1) }
        #expect(try Data(contentsOf: url) == original)
    }
}
