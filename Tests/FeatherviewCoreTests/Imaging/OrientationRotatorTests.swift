import CoreGraphics
import Foundation
import ImageIO
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

    /// "ab/cd" after `change`, as shown.
    static func changed(_ corners: String, _ change: OrientationChange) -> String {
        let c = Array(corners)
        return switch change {
        case .flip(let flip): mirrored(corners, flip)
        case .rotate(.clockwise): String([c[3], c[0], "/", c[4], c[1]])
        case .rotate(.counterClockwise): String([c[1], c[4], "/", c[0], c[3]])
        }
    }

    /// The stored pixels (orientation not applied) and the gain map's bytes: what a lossless change keeps.
    @available(macOS 15, *)
    static func storedData(_ url: URL) -> (pixels: Data?, gainMap: Data?, colorSpace: String?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return (nil, nil, nil) }
        let gainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
            as? [CFString: Any]
        return (image.dataProvider?.data as Data?, gainMap?[kCGImageAuxiliaryDataInfoData] as? Data,
                image.colorSpace?.name as String?)
    }

    /// ImageIO's upright HDR decode's corners as in `Fixtures.corners`: "+" brighter than SDR white, "-" not.
    @available(macOS 15, *)
    static func brightCorners(of url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
                  kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
              ] as CFDictionary) else { return "" }
        let (width, height) = (image.width, image.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                    bytesPerRow: width * 16, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func bright(_ x: Int, _ y: Int) -> String {  // row 0 is the top
            let i = (y * width + x) * 4
            return pixels[i] + pixels[i + 1] + pixels[i + 2] > 3 ? "+" : "-"
        }
        let (l, t, r, b) = (4, 4, width - 5, height - 5)
        return bright(l, t) + bright(r, t) + "/" + bright(l, b) + bright(r, b)
    }

    /// Red and white are the fixture's bright quadrants.
    static func expectedBright(_ corners: String) -> String {
        String(corners.map { $0 == "/" ? "/" : "RW".contains($0) ? "+" : "-" })
    }

    enum HDRKind: CaseIterable { case gainMapHEIC, gainMapJPEG, pqHEIC }

    @Test(arguments: HDRKind.allCases, 1...8)
    func hdrFilesTurnAndFlipLosslessly(_ kind: HDRKind, _ orientation: Int) throws {
        guard #available(macOS 15, *) else { return }
        let changes: [OrientationChange] = [.rotate(.clockwise), .rotate(.counterClockwise),
                                            .flip(.horizontal), .flip(.vertical)]
        for change in changes {
            let dir = try Fixtures.makeTempDir()
            let url = try Fixtures.writeHDRGainMap(
                to: dir.appendingPathComponent(kind == .gainMapJPEG ? "h.jpg" : "h.heic"),
                type: kind == .gainMapJPEG ? .jpeg : .heic, orientation: orientation, pq: kind == .pqHEIC)
            let before = Fixtures.corners(of: url)
            let stored = Self.storedData(url)
            #expect(before.count == 5 && !before.contains("?"), "\(before)")
            #expect(stored.pixels != nil && (stored.gainMap != nil) == (kind != .pqHEIC))
            if kind != .pqHEIC { #expect(Self.brightCorners(of: url) == Self.expectedBright(before)) }

            try OrientationRotator.apply(url, change)

            #expect(Fixtures.corners(of: url) == Self.changed(before, change), "\(kind) \(orientation) \(change)")
            // The gain map's brightness turns with the picture.
            if kind != .pqHEIC {
                #expect(Self.brightCorners(of: url) == Self.expectedBright(Self.changed(before, change)),
                        "\(kind) \(orientation) \(change)")
            }
            let after = Self.storedData(url)
            #expect(after.pixels == stored.pixels && after.gainMap == stored.gainMap
                    && after.colorSpace == stored.colorSpace, "\(kind) \(orientation) \(change)")
            if kind == .gainMapHEIC {  // ImageIO reports irot/imir; the Exif tag must agree for other tools
                #expect(HEIFLayout.exifOrientation(try Data(contentsOf: url))
                        == OrientationRotator.next(orientation, change), "\(kind) \(orientation) \(change)")
            }
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix(".featherview-") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test func gainMapHEICInReadOnlyFolderLeavesOriginalIntact() throws {
        guard #available(macOS 15, *) else { return }
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeHDRGainMap(to: dir.appendingPathComponent("gm.heic"))
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        #expect(throws: RotateError.writeFailed) { try OrientationRotator.rotate(url, .clockwise) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func refusesUnsupportedFormatsAndLeavesThemUntouched() throws {
        let dir = try Fixtures.makeTempDir()
        let files = [
            try Fixtures.writeImage(to: dir.appendingPathComponent("p.png"), width: 4, height: 4, type: .png),
            try Fixtures.writeImage(to: dir.appendingPathComponent("png.jpg"), width: 4, height: 4, type: .png),
            try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1]),
            try Fixtures.writeHEICS(to: dir.appendingPathComponent("s.heics"), delays: [0.1, 0.1]),
            // Featherview's own formats, which ImageIO can't even identify.
            try { () throws -> URL in
                let url = dir.appendingPathComponent("q.qoi")
                try QOICodec.encode(RGBAImage(width: 4, height: 4)).write(to: url)
                return url
            }(),
        ]
        for url in files {
            let original = try Data(contentsOf: url)
            #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.apply(url, .flip(.horizontal)) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func refusesLaterTIFFPagesAndLeavesThemUntouched() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let original = try Data(contentsOf: url)
        // Turning a later page means re-encoding every page (lossy for JPEG-compressed TIFFs).
        #expect(throws: RotateError.notFirstPage) { try OrientationRotator.apply(url, .flip(.vertical), page: 1) }
        #expect(try Data(contentsOf: url) == original)
    }
}
