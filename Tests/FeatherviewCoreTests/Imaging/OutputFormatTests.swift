import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct FormatRegistryTests {
    @Test func writesEverySpecFormatAndHidesTextures() {
        let ids = Set(FormatRegistry.writable.map(\.id))
        // docs/spec.md "Formats": ImageIO's list plus our own encoders.
        for id in ["jpg", "png", "heic", "avif", "tiff", "gif", "jp2", "pdf", "psd", "tga", "ico", "icns",
                   "exr", "pbm", "bmp", "pgm", "ppm", "qoi", "pcx", "webp", "jxl"] {
            #expect(ids.contains(id), "\(id)")
        }
        for hidden in ["ktx", "ktx2", "astc", "pvr", "dds", "atx", "heics"] { #expect(!ids.contains(hidden)) }
        #expect(ids.count == FormatRegistry.writable.count)  // ids are unique
    }

    @Test func sortedByName() {
        let names = FormatRegistry.writable.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func defaultsFollowTheSpec() throws {
        #expect(OutputFormat.jpeg.defaultOptions.quality == 80)
        #expect(OutputFormat.jpeg.defaultOptions.keepMetadata)
        let jp2 = try #require(FormatRegistry.format(id: "jp2"))
        #expect(jp2.defaultOptions.lossless && jp2.defaultOptions.quality == 90)
        let pdf = try #require(FormatRegistry.format(id: "pdf"))
        #expect(!pdf.defaultOptions.lossless && pdf.defaultOptions.quality == 95)
        #expect(FormatRegistry.format(id: "gif")?.optionFields == [])
    }

    @Test func webpFollowsTheSpec() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        #expect(webp.name == "WebP" && webp.fileExtension == "webp" && webp.writer == .webp)
        #expect(webp.optionFields == [.webpKind, .lossless, .quality, .effort])
        let d = webp.defaultOptions
        #expect(d.quality == 75 && !d.lossless && d.effort == 4 && d.webpKind == .photo)
        #expect(webp.type?.identifier == "org.webmproject.webp")
    }

    // A newer macOS that writes WebP itself must not add a second "WebP" entry.
    @Test func onlyOneWebPEntry() {
        #expect(FormatRegistry.writable.filter { $0.fileExtension == "webp" }.count == 1)
        #expect(FormatRegistry.hidden.contains("org.webmproject.webp"))
    }

    @Test func jxlFollowsThePlan() throws {
        let jxl = try #require(FormatRegistry.format(id: "jxl"))
        #expect(jxl.name == "JPEG XL" && jxl.fileExtension == "jxl" && jxl.writer == .jxl)
        #expect(jxl.optionFields == [.lossless, .quality, .effort, .keepMetadata])
        let d = jxl.defaultOptions
        #expect(d.quality == 90 && d.effort == 7 && !d.lossless && d.keepMetadata)
        #expect(jxl.type?.identifier == "public.jpeg-xl")
        #expect(FormatRegistry.writable.filter { $0.fileExtension == "jxl" }.count == 1)
        #expect(FormatRegistry.hidden.contains("public.jpeg-xl"))
        #expect(jxl.effortRange == 1...9)
        #expect(try #require(FormatRegistry.format(id: "webp")).effortRange == 0...6)
    }

    @Test func oldStoredOptionsGetWebPDefaults() throws {
        // What milestone 3 stored for JPEG: no effort, no webpKind.
        let json = Data(#"{"quality":55,"lossless":false,"progressive":true,"keepMetadata":false,"interlaced":false,"tiffCompression":5,"keepAllPages":true}"#.utf8)
        let options = try JSONDecoder().decode(FormatOptions.self, from: json)
        #expect(options.quality == 55 && options.progressive && !options.keepMetadata)
        #expect(options.effort == 4 && options.webpKind == .photo)
        let again = try JSONDecoder().decode(FormatOptions.self, from: JSONEncoder().encode(
            options.with { $0.effort = 6; $0.webpKind = .drawing }))
        #expect(again.effort == 6 && again.webpKind == .drawing)
    }

    @Test func readableNamesListMacOSAndOwnFormats() {
        let names = FormatRegistry.readableNames
        #expect(names.macOS.contains("JPEG") && names.macOS.contains("HEIC"))
    }
}

@Suite struct ImageEncoderTests {
    func image(_ width: Int = 40, _ height: Int = 30, alpha: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        for y in 0..<height { for x in 0..<width {
            context.setFillColor(CGColor(red: Double(x) / Double(width), green: Double(y) / Double(height), blue: 0.5, alpha: alpha ? 0.5 : 1))
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        } }
        return context.makeImage()!
    }

    @Test func webpUsesItsOptions() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        let lossy = try ImageEncoder.encode([image(200, 150)], as: webp, options: webp.defaultOptions)
        let lossless = try ImageEncoder.encode([image(200, 150)], as: webp, options: webp.defaultOptions.with { $0.lossless = true })
        let source = try #require(CGImageSourceCreateWithData(lossy as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "org.webmproject.webp")
        #expect(lossy != lossless)
        let losslessSource = try #require(CGImageSourceCreateWithData(lossless as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(losslessSource, 0, nil))
        let back = try #require(RGBAImage(decoded))
        #expect(back == (try ImageEncoder.rgba(image(200, 150))))
    }

    @Test func jxlUsesItsOptions() throws {
        _ = Fixtures.jxl
        let jxl = try #require(FormatRegistry.format(id: "jxl"))
        let lossless = try ImageEncoder.encode([image(200, 150)], as: jxl, options: jxl.defaultOptions.with { $0.lossless = true })
        let source = try #require(CGImageSourceCreateWithData(lossless as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg-xl")
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(try #require(RGBAImage(decoded)) == (try ImageEncoder.rgba(image(200, 150))))
        let low = try ImageEncoder.encode([image(200, 150)], as: jxl, options: jxl.defaultOptions.with { $0.quality = 20 })
        let high = try ImageEncoder.encode([image(200, 150)], as: jxl, options: jxl.defaultOptions.with { $0.quality = 95 })
        #expect(low.count < high.count)
    }

    @Test func rotatedPhotoKeepsMetadataUpright() throws {
        _ = Fixtures.jxl
        let jxl = try #require(FormatRegistry.format(id: "jxl"))
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(
            to: dir.appendingPathComponent("portrait.jpg"), width: 40, height: 20, orientation: 6,
            properties: [
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 17"],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:05:01 12:00:00",
                                                 kCGImagePropertyExifFNumber: 2.8],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.5, kCGImagePropertyGPSLatitudeRef: "N"],
            ])
        let pages = try ImageSaver.pages(of: input, for: jxl, options: jxl.defaultOptions)

        let data = try ImageEncoder.encode(pages, as: jxl, options: jxl.defaultOptions, metadataFrom: input)

        let p = try props(data)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 20 && p[kCGImagePropertyPixelHeight] as? Int == 40)
        #expect(p[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifFNumber] as? Double == 2.8)
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:05:01 12:00:00")
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "iPhone 17")
        #expect((p[kCGImagePropertyGPSDictionary] as? [CFString: Any])?[kCGImagePropertyGPSLatitude] as? Double == 52.5)

        let stripped = try props(ImageEncoder.encode(pages, as: jxl, options: jxl.defaultOptions.with { $0.keepMetadata = false },
                                                     metadataFrom: input))
        #expect((stripped[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    }

    @Test func sixteenBitSourceEncodes() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 16, bytesPerRow: 0,
                                             space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let source = try #require(context.makeImage())
        let data = try ImageEncoder.encode([source], as: webp, options: webp.defaultOptions)
        let readBack = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(readBack, 0, nil))
        #expect(decoded.width == 32 && decoded.height == 24)
    }

    func props(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test(arguments: FormatRegistry.writable)
    func everyFormatWritesSomethingReadable(format: OutputFormat) throws {
        let data = try ImageEncoder.encode([image()], as: format, options: format.defaultOptions)
        #expect(data.count > 0)
        guard case .imageIO = format.writer else { return }  // own formats are checked by their codec tests
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) >= 1)
    }

    @Test func jpegProgressiveAndQuality() throws {
        let low = try ImageEncoder.encode([image()], as: .jpeg, options: FormatOptions().with { $0.quality = 10 })
        let high = try ImageEncoder.encode([image()], as: .jpeg, options: FormatOptions().with { $0.quality = 95 })
        #expect(low.count < high.count)
        let progressive = try ImageEncoder.encode([image()], as: .jpeg, options: FormatOptions().with { $0.progressive = true })
        let jfif = try props(progressive)[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
        #expect(jfif?[kCGImagePropertyJFIFIsProgressive] as? Bool == true)
    }

    @Test func jpegTargetSizeFitsAndUsesTheHighestQualityThatDoes() throws {
        let big = image(400, 300)
        let limit = 12  // KB
        let data = try ImageEncoder.encode([big], as: .jpeg, options: FormatOptions().with { $0.targetSizeKB = limit })
        #expect(data.count <= limit * 1024)
        let unlimited = try ImageEncoder.encode([big], as: .jpeg, options: FormatOptions().with { $0.quality = 100 })
        #expect(unlimited.count > limit * 1024)  // the limit really made it smaller
        // A limit nothing reaches still writes the smallest file instead of failing.
        let tiny = try ImageEncoder.encode([big], as: .jpeg, options: FormatOptions().with { $0.targetSizeKB = 1 })
        #expect(tiny.count > 0)
    }

    @Test func jpegTargetSizeTooBigToCountInBytesStillWrites() throws {
        let huge = 10_000_000_000_000_000  // KB; times 1024 overflows Int
        let data = try ImageEncoder.encode([image()], as: .jpeg, options: FormatOptions().with { $0.targetSizeKB = huge })
        #expect(data.count > 0)
    }

    @Test func pngInterlaced() throws {
        let data = try ImageEncoder.encode([image()], as: .png, options: FormatOptions().with { $0.interlaced = true })
        let png = try props(data)[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(png?[kCGImagePropertyPNGInterlaceType] as? Int == 1)
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func encodeWritesDateTaken(_ format: OutputFormat) throws {
        let date = "2024:07:01 12:00:00"
        let data = try ImageEncoder.encode([image()], as: format, options: FormatOptions().with { $0.keepMetadata = false },
                                           dateTaken: date)
        let properties = try props(data)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == date)
        #expect(exif?[kCGImagePropertyExifDateTimeDigitized] as? String == date)
        if format.id == "jpg" {
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect(tiff?[kCGImagePropertyTIFFDateTime] as? String == date)
        }
    }

    @Test(arguments: TIFFCompression.allCases)
    func tiffCompression(_ compression: TIFFCompression) throws {
        let data = try ImageEncoder.encode([image()], as: .tiff, options: FormatOptions().with { $0.tiffCompression = compression })
        let tiff = try props(data)[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFCompression] as? Int == compression.rawValue)
    }

    @Test func tiffKeepsAllPagesOnlyWhenAsked() throws {
        let pages = [image(), image(20, 10), image(10, 5)]
        let all = try ImageEncoder.encode(pages, as: .tiff, options: FormatOptions())
        let first = try ImageEncoder.encode(pages, as: .tiff, options: FormatOptions().with { $0.keepAllPages = false })
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithData(all as CFData, nil)!) == 3)
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithData(first as CFData, nil)!) == 1)
        let png = try ImageEncoder.encode(pages, as: .png, options: FormatOptions())
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithData(png as CFData, nil)!) == 1)
    }

    @Test func jpeg2000LosslessIsExact() throws {
        let jp2 = try #require(FormatRegistry.format(id: "jp2"))
        let original = image()
        let data = try ImageEncoder.encode([original], as: jp2, options: jp2.defaultOptions)
        let back = try #require(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil))
        #expect(RGBAImage(back) == RGBAImage(original))
    }

    @Test func avifAtQuality100StillWrites() throws {
        let avif = try #require(FormatRegistry.format(id: "avif"))
        let data = try ImageEncoder.encode([image()], as: avif, options: FormatOptions().with { $0.quality = 100 })
        #expect(data.count > 0)
    }

    @Test func iconsFitAnAllowedSquare() throws {
        let ico = try #require(FormatRegistry.format(id: "ico"))
        let icns = try #require(FormatRegistry.format(id: "icns"))
        let bigICO = try props(ImageEncoder.encode([image(400, 300)], as: ico, options: FormatOptions()))
        #expect(bigICO[kCGImagePropertyPixelWidth] as? Int == 256 && bigICO[kCGImagePropertyPixelHeight] as? Int == 256)
        let smallICNS = try props(ImageEncoder.encode([image(100, 40)], as: icns, options: FormatOptions()))
        #expect(smallICNS[kCGImagePropertyPixelWidth] as? Int == 128)
    }

    func pdfText(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func pdfEmbedsJPEGUnlessLosslessOrTransparent() throws {
        let pdf = try #require(FormatRegistry.format(id: "pdf"))
        let lossy = try ImageEncoder.encode([image()], as: pdf, options: pdf.defaultOptions)
        #expect(pdfText(lossy).contains("/DCTDecode"))
        let lossless = try ImageEncoder.encode([image()], as: pdf, options: pdf.defaultOptions.with { $0.lossless = true })
        #expect(!pdfText(lossless).contains("/DCTDecode"))
        let transparent = try ImageEncoder.encode([image(alpha: true)], as: pdf, options: pdf.defaultOptions)
        #expect(!pdfText(transparent).contains("/DCTDecode"))
    }

    @Test func pdfHasOnePagePerImageAtItsSize() throws {
        let pdf = try #require(FormatRegistry.format(id: "pdf"))
        let data = try ImageEncoder.encode([image(40, 30), image(20, 10)], as: pdf, options: pdf.defaultOptions)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 2)
        #expect(document.page(at: 2)?.getBoxRect(.mediaBox).size == CGSize(width: 20, height: 10))
    }

    @Test func noPagesThrows() {
        #expect(throws: EncodeError.failed) { try ImageEncoder.encode([], as: .png, options: FormatOptions()) }
    }
}

@Suite struct FormatSettingsTests {
    let defaults = UserDefaults(suiteName: "FormatSettingsTests-\(UUID().uuidString)")!

    @Test func optionsAreRememberedPerFormat() {
        #expect(FormatSettings.options(for: .jpeg, in: defaults) == OutputFormat.jpeg.defaultOptions)
        FormatSettings.save(FormatOptions().with { $0.quality = 55 }, for: .jpeg, in: defaults)
        #expect(FormatSettings.options(for: .jpeg, in: defaults).quality == 55)
        #expect(FormatSettings.options(for: .heic, in: defaults).quality == 80)
    }

    @Test func damagedOrOldStoredOptionsFallBackToDefaults() {
        defaults.set(Data("nonsense".utf8), forKey: "formatOptions.jpg")
        #expect(FormatSettings.options(for: .jpeg, in: defaults) == OutputFormat.jpeg.defaultOptions)
        // Stored before an option existed: the others are kept, the new one gets its default.
        defaults.set(Data(#"{"quality": 42}"#.utf8), forKey: "formatOptions.jpg")
        let options = FormatSettings.options(for: .jpeg, in: defaults)
        #expect(options.quality == 42 && options.keepMetadata)
    }

    @Test func profilesSaveReplaceAndDelete() {
        FormatSettings.saveProfile("web", FormatOptions().with { $0.quality = 70 }, for: .jpeg, in: defaults)
        FormatSettings.saveProfile("Archive", FormatOptions().with { $0.quality = 95 }, for: .jpeg, in: defaults)
        FormatSettings.saveProfile("web", FormatOptions().with { $0.quality = 60 }, for: .jpeg, in: defaults)
        FormatSettings.saveProfile("  ", FormatOptions(), for: .jpeg, in: defaults)
        let profiles = FormatSettings.profiles(for: .jpeg, in: defaults)
        #expect(profiles.map(\.name) == ["Archive", "web"])
        #expect(profiles.last?.options.quality == 60)
        FormatSettings.deleteProfile("Archive", for: .jpeg, in: defaults)
        #expect(FormatSettings.profiles(for: .jpeg, in: defaults).map(\.name) == ["web"])
        #expect(FormatSettings.profiles(for: .png, in: defaults).isEmpty)
    }

    @Test func unknownLastFormatFallsBackToJPEG() {
        defaults.set("no-such-format", forKey: FormatSettings.lastSaveFormat.key)
        #expect(FormatSettings.lastFormat(in: defaults) == .jpeg)
        defaults.set("png", forKey: FormatSettings.lastSaveFormat.key)
        #expect(FormatSettings.lastFormat(in: defaults) == .png)
    }
}

@Suite struct ImageSaverTests {
    @Test func savesUprightAtFullSize() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 40, height: 20, orientation: 6)
        let target = dir.appendingPathComponent("a.png")
        try ImageSaver.save(source, page: 0, to: target, as: .png, options: FormatOptions())
        #expect(ImageDecoder.displaySize(of: target) == CGSize(width: 20, height: 40))
    }

    @Test func replacesOnlyOnceTheNewFileIsWritten() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let target = dir.appendingPathComponent("b.png")
        try Data("old".utf8).write(to: target)
        try ImageSaver.save(source, page: 0, to: target, as: .png, options: FormatOptions())
        #expect(ImageDecoder.displaySize(of: target) == CGSize(width: 8, height: 8))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["a.jpg", "b.png"])  // no temp left

        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        #expect(throws: DecodeError.self) { try ImageSaver.save(bad, page: 0, to: target, as: .png, options: FormatOptions()) }
        #expect(ImageDecoder.displaySize(of: target) == CGSize(width: 8, height: 8))  // untouched
    }

    @Test func savingOverTheSourceWorks() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 30, height: 10, orientation: 6)
        try ImageSaver.save(source, page: 0, to: source, as: .jpeg, options: FormatOptions())
        #expect(ImageDecoder.displaySize(of: source) == CGSize(width: 10, height: 30))
    }

    @Test func replacingASymlinkReplacesItsTarget() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 4)
        let other = dir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let real = try Fixtures.writeImage(to: other.appendingPathComponent("real.png"), width: 2, height: 2)
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try ImageSaver.save(source, page: 0, to: link, as: .png, options: FormatOptions())
        #expect(ImageDecoder.displaySize(of: real) == CGSize(width: 8, height: 4))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)  // still a link
    }

    @Test func refusesToReplaceAFolder() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let folder = dir.appendingPathComponent("x.png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: folder.appendingPathComponent("inner.txt"))
        #expect(throws: (any Error).self) { try ImageSaver.save(source, page: 0, to: folder, as: .png, options: FormatOptions()) }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("inner.txt").path))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["a.jpg", "x.png"])  // no temp left
    }

    @Test func pagesForTIFFAndPDF() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("p.tiff"), pages: 3)
        let pdf = try #require(FormatRegistry.format(id: "pdf"))
        #expect(try ImageSaver.pages(of: tiff, page: 1, for: .tiff, options: FormatOptions()).count == 3)
        #expect(try ImageSaver.pages(of: tiff, page: 1, for: .tiff, options: FormatOptions().with { $0.keepAllPages = false }).map(\.width) == [9])
        #expect(try ImageSaver.pages(of: tiff, page: 1, for: pdf, options: pdf.defaultOptions).count == 3)
        #expect(try ImageSaver.pages(of: tiff, page: 2, for: .png, options: FormatOptions()).map(\.width) == [10])
    }
}

@Suite struct SaveNameTests {
    // The save panel would otherwise use the UTType's preferred extension: .pbm for PGM/PPM, .jpeg for JPEG.
    @Test func usesTheFormatsOwnExtension() throws {
        let photo = URL(fileURLWithPath: "/tmp/photo.jpg")
        for (id, name) in [("jpg", "photo.jpg"), ("pgm", "photo.pgm"), ("ppm", "photo.ppm"), ("png", "photo.png")] {
            #expect(try #require(FormatRegistry.format(id: id)).fileName(for: photo) == name)
        }
        #expect(OutputFormat.jpeg.fileName(for: URL(fileURLWithPath: "/tmp/a.b.tif")) == "a.b.jpg")
    }

    @Test func extensionIsOneItsTypeAccepts() {
        // Otherwise NSSavePanel appends the type's preferred extension to our name.
        for format in FormatRegistry.writable {
            let extensions = format.type?.tags[.filenameExtension] ?? []
            #expect(extensions.contains(format.fileExtension), "\(format.id)")
        }
    }
}

@Suite struct DesktopFormatTests {
    @Test func desktopCanShow() {
        for ext in ["jpg", "heic", "png"] {
            #expect(ImageFormats.desktopCanShow(URL(fileURLWithPath: "/a.\(ext)")), "\(ext)")
        }
        for ext in ["qoi", "xcf", "pdf"] {
            #expect(!ImageFormats.desktopCanShow(URL(fileURLWithPath: "/a.\(ext)")), "\(ext)")
        }
    }
}
