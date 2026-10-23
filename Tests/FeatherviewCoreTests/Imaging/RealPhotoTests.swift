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

    /// The formats Save As writes in this process: ImageIO's photo formats, WebP and JPEG XL.
    static let saveFormats: [OutputFormat] = {
        _ = Fixtures.jxl
        return ["jpg", "png", "heic", "tiff", "webp", "avif", "jxl"].compactMap(FormatRegistry.format(id:))
    }()

    static func gps(_ url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return p[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    }

    /// Upright pixels at the displayed size, tag 1; date, GPS and profile kept where the format keeps metadata
    /// (spec "Output"); a gain map kept in HEIC and AVIF (spec "Formats").
    // One photo at a time (its formats in parallel): dozens of parallel HEIC encodes off the pool block every dispatch thread.
    @Test(.serialized, arguments: photos) func saveAsIsUprightWithMetadata(_ url: URL) async throws {
        let file = try Self.copy(url)
        let before = try Self.facts(file)
        let display = try #require(ImageDecoder.displaySize(of: file))
        let hasGPS = Self.gps(file) != nil
        let out = try Fixtures.makeTempDir()
        let targets = Self.saveFormats.map { out.appendingPathComponent($0.fileName(for: file)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (format, target) in zip(Self.saveFormats, targets) {
                // AVIF's encoder needs a free cooperative-pool thread: off the pool, as Save As runs it.
                group.addTask { try await offPool { try ImageSaver.save(file, page: 0, to: target, as: format, options: format.defaultOptions) } }
            }
            try await group.waitForAll()
        }
        for (format, target) in zip(Self.saveFormats, targets) {
            _ = try ImageDecoder.decode(target, maxPixelSize: 256)
            let after = try Self.facts(target)
            #expect(after.orientation == 1, "\(format.name)")
            #expect(CGSize(width: after.width, height: after.height) == display, "\(format.name)")
            switch format.writer {
            case .webp: #expect(after.profile == nil, "WebP")  // our encoder converts to sRGB, written without a profile
            case .jxl: break  // libjxl describes the colours by their primaries, under a name of its own
            default:  // an untagged source is sRGB, and is written tagged so
                if let profile = before.profile { #expect(after.profile == profile, "\(format.name)") }
            }
            if format.writer != .webp {  // libwebp writes no metadata
                #expect(after.date == before.date, "\(format.name)")
                #expect((Self.gps(target) != nil) == hasGPS, "\(format.name)")
            }
            if ImageDecoder.supportsHDR, before.gainMap || before.isoGainMap, ["heic", "avif"].contains(format.id) {
                #expect(after.gainMap || after.isoGainMap, "\(format.name)")
            }
        }
    }

    /// Copies of every photo in one folder, numbered: two subfolders may hold the same name.
    static func copies() throws -> [URL] {
        let folder = try Fixtures.makeTempDir()
        return try photos.enumerated().map { index, url in
            let target = folder.appendingPathComponent("\(index)-\(url.lastPathComponent)")
            try FileManager.default.copyItem(at: url, to: target)
            return target
        }
    }

    static func jpegJob(_ inputs: [URL], into out: URL) -> BatchJob {
        var s = BatchSettings()
        s.formatID = "jpg"
        s.outputFolder = out.path
        return BatchJob(inputs: inputs.map { BatchInput(url: $0) }, settings: s)
    }

    @Test func batchConvertsTheCorpus() async throws {
        let inputs = try Self.copies(), out = try Fixtures.makeTempDir()
        let results = await BatchConverter.run(Self.jpegJob(inputs, into: out))
        #expect(results.filter { $0.status != .converted }.map(\.logLine) == [])
        #expect(results.map(\.input) == inputs)
        #expect(results.allSatisfy { $0.outputs.count == 1 })
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == inputs.count)
    }

    @Test func batchTwiceNeverOverwrites() async throws {
        let inputs = try Self.copies(), out = try Fixtures.makeTempDir()
        let first = await BatchConverter.run(Self.jpegJob(inputs, into: out))
        let firstBytes = try first.map { try Data(contentsOf: try #require($0.output)) }
        let second = await BatchConverter.run(Self.jpegJob(inputs, into: out))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == 2 * inputs.count)
        for (a, b) in zip(first, second) {
            let a = try #require(a.output), b = try #require(b.output)
            #expect(b.lastPathComponent == a.deletingPathExtension().lastPathComponent + " 2.jpg")
        }
        #expect(try first.map { try Data(contentsOf: try #require($0.output)) } == firstBytes)
    }
}
