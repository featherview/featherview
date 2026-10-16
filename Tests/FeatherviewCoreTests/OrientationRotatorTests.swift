import CoreGraphics
import Foundation
import Testing
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
}
