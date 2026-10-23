import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

/// Real camera files from `FEATHERVIEW_SAMPLES/photos/` (any subfolder), worked on as copies.
@Suite(.enabled(if: SampleCorpus.isAvailable)) struct RealPhotoTests {
    static let photos: [URL] = {
        guard let root = SampleCorpus.root?.appendingPathComponent("photos"),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.path < $1.path }
    }()

    struct Facts: Equatable {
        var orientation: Int, width: Int, height: Int, date: String?, gainMap: Bool, isoGainMap: Bool, profile: String?
    }

    static func facts(_ url: URL) throws -> Facts {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let p = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        var isoGainMap = false
        if #available(macOS 15, *) {
            isoGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
        }
        return Facts(orientation: p[kCGImagePropertyOrientation] as? Int ?? 1,
                     width: p[kCGImagePropertyPixelWidth] as? Int ?? 0, height: p[kCGImagePropertyPixelHeight] as? Int ?? 0,
                     date: exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
                     gainMap: CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil,
                     isoGainMap: isoGainMap,
                     profile: p[kCGImagePropertyProfileName] as? String)
    }

    /// The stored pixels, untransformed. After a lossless change they differ by at most 1 per channel:
    /// ImageIO may rewrite a JPEG's header segments, and the decoder then rounds differently (scan data unchanged).
    static func storedPixels(_ url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data as Data?)
    }

    static func copy(_ url: URL) throws -> URL {
        let target = try Fixtures.makeTempDir().appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    @Test func corpusIsThere() {
        #expect(!Self.photos.isEmpty)
    }

    @Test(arguments: photos) func decodesForScreenAndHDR(_ url: URL) throws {
        let display = try #require(ImageDecoder.displaySize(of: url))
        let image = try ImageDecoder.decode(url, maxPixelSize: 2048, halvingSteps: true)
        #expect(max(image.width, image.height) >= 1024 || Int(max(display.width, display.height)) < 2048)
        if ImageDecoder.supportsHDR, try Self.facts(url).gainMap || Self.facts(url).isoGainMap {
            _ = try ImageDecoder.decode(url, maxPixelSize: 2048, hdr: true)
        }
        _ = try ImageDecoder.thumbnail(url, side: 256, colorSpace: nil)
    }

    /// Every change sets the expected tag and keeps pixels, date, gain map and profile; four turns are identity.
    @Test(arguments: photos) func rotateAndFlipAreLossless(_ url: URL) throws {
        let file = try Self.copy(url)
        let before = try Self.facts(file)
        let type = UTType(filenameExtension: file.pathExtension)
        guard OrientationRotator.supported.contains(where: { type?.conforms(to: $0) == true }) else {
            let original = try Data(contentsOf: file)
            #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.rotate(file, .clockwise) }
            #expect(try Data(contentsOf: file) == original)
            return
        }
        let pixels = try Self.storedPixels(file)
        var expected = before
        for change: OrientationChange in [.rotate(.clockwise), .flip(.horizontal), .flip(.vertical), .rotate(.counterClockwise)] {
            try OrientationRotator.apply(file, change)
            expected.orientation = OrientationRotator.next(expected.orientation, change)
            #expect(try Self.facts(file) == expected, "\(change)")
        }
        for _ in 0..<4 { try OrientationRotator.rotate(file, .clockwise) }
        #expect(try Self.facts(file) == expected)
        let after = try Self.storedPixels(file)
        #expect(after.count == pixels.count && zip(after, pixels).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }
}
