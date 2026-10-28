import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ImageInfoTests {
    private func info(_ properties: [CFString: Any], type: UTType = .jpeg, name: String = "a.jpg") throws -> ImageInfo {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 8, height: 8, type: type,
                                          properties: properties)
        return ImageInfo.read(url)
    }

    private func exif(_ values: [CFString: Any]) throws -> ImageInfo {
        try info([kCGImagePropertyExifDictionary: values])
    }

    private func pure(_ props: [CFString: Any], metadata: CGImageMetadata? = nil, fileSize: Int? = nil) -> ImageInfo {
        ImageInfo.read(properties: props, metadata: metadata, url: URL(fileURLWithPath: "/tmp/a.jpg"), fileSize: fileSize)
    }

    @Test func exposureTilesAreBareNumbers() throws {
        let e = try exif([
            kCGImagePropertyExifExposureTime: 1.0 / 250,
            kCGImagePropertyExifFNumber: 8.0,
            kCGImagePropertyExifISOSpeedRatings: [100],
            kCGImagePropertyExifFocalLength: 35.0,
        ]).exposure
        #expect(e.shutter == "1/250")
        #expect(e.aperture == "8")
        #expect(e.iso == "100")
        #expect(e.focal == "35")
    }

    @Test func focal35OnlyWhenDifferent() throws {
        let differs = try exif([kCGImagePropertyExifFocalLength: 35.0, kCGImagePropertyExifFocalLenIn35mmFilm: 53])
        #expect(differs.exposure.focal35 == "53 mm")
        let same = try exif([kCGImagePropertyExifFocalLength: 35.0, kCGImagePropertyExifFocalLenIn35mmFilm: 35])
        #expect(same.exposure.focal35 == nil)
    }

    @Test func chips() {
        func e(_ values: [CFString: Any]) -> ImageInfo.Exposure { pure([kCGImagePropertyExifDictionary: values]).exposure }
        #expect(e([kCGImagePropertyExifExposureBiasValue: -0.7]).bias == "−0.7 EV")
        #expect(e([kCGImagePropertyExifFlash: 16]).flash == "No flash")
        #expect(e([kCGImagePropertyExifFlash: 1]).flash == "Flash")
        #expect(e([kCGImagePropertyExifWhiteBalance: 0]).whiteBalance == "Auto")
        #expect(e([kCGImagePropertyExifMeteringMode: 5]).metering == "Multi-segment")
        #expect(e([kCGImagePropertyExifMeteringMode: 2]).metering == "Centre-weighted")
        #expect(e([kCGImagePropertyExifMeteringMode: 3]).metering == "Spot")
    }

    // ByteCountFormatter's file style counts 1,000 bytes to the KB, as Finder does: 487,424 bytes is 487 KB.
    @Test func formatLine() {
        let props: [CFString: Any] = [kCGImagePropertyPixelWidth: 3000, kCGImagePropertyPixelHeight: 2000]
        #expect(pure(props, fileSize: 487_424).formatLine == "JPEG · 3,000 × 2,000 · 487 KB")
        var turned = props
        turned[kCGImagePropertyOrientation] = 6
        #expect(pure(turned, fileSize: 487_424).formatLine == "JPEG · 2,000 × 3,000 · 487 KB")
        #expect(pure(props).picture.dimensions == "3,000 × 2,000 · 6.0 MP")
    }

    @Test func formatLineFollowsSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 8, height: 8)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(ImageInfo.read(target).formatLine.components(separatedBy: " · ").count == 3)  // size included
        #expect(ImageInfo.read(link).formatLine == ImageInfo.read(target).formatLine)
    }

    @available(macOS 15, *)
    @Test func pictureSummary() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeHDRGainMap(to: dir.appendingPathComponent("hdr.heic"))
        let picture = ImageInfo.read(url).picture
        #expect(picture.summary == "P3 · 8-bit · HDR")
        #expect(picture.profile == "Display P3")
        #expect(picture.bitDepth == "8 bits per channel")
        #expect((picture.headroom ?? 0) > 1)
        #expect(picture.hdr?.hasPrefix("Gain map, up to ") == true)
        #expect(picture.hdr?.hasSuffix("×") == true)
    }

    private func gps(_ values: [CFString: Any]) -> ImageInfo.GPS? {
        pure([kCGImagePropertyGPSDictionary: values]).gps
    }

    @Test func gpsSignsFromRefs() throws {
        let north = try info([kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 46.6356, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 8.5939, kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSAltitude: 1447.0,
        ] as [CFString: Any]]).gps
        #expect(north == ImageInfo.GPS(latitude: 46.6356, longitude: 8.5939, altitude: 1447))
        let south = gps([
            kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2093, kCGImagePropertyGPSLongitudeRef: "W",
        ])
        #expect(south == ImageInfo.GPS(latitude: -33.8688, longitude: -151.2093, altitude: nil))
    }

    @Test func gpsMissingHalfIsDropped() {
        #expect(gps([kCGImagePropertyGPSLatitude: 46.6356, kCGImagePropertyGPSLatitudeRef: "N"]) == nil)
    }

    @Test func nullIslandIsNoFix() {
        #expect(gps([kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLongitude: 0.0]) == nil)
        #expect(gps([kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLongitude: 0.0,
                     kCGImagePropertyGPSAltitude: 12.0]) != nil)
    }

    // Bad DMS rationals in a corrupt file give a latitude past 90 or a zero denominator's inf/NaN.
    @Test func gpsOutOfRangeIsNoFix() {
        func fix(_ lat: Double, _ lon: Double) -> ImageInfo.GPS? {
            gps([kCGImagePropertyGPSLatitude: lat, kCGImagePropertyGPSLongitude: lon])
        }
        #expect(fix(212, 8) == nil)
        #expect(fix(46, 181) == nil)
        #expect(fix(.infinity, 8) == nil)
        #expect(fix(46, .nan) == nil)
        #expect(fix(90, -180) != nil)
        let badAltitude = gps([kCGImagePropertyGPSLatitude: 46.0, kCGImagePropertyGPSLongitude: 8.0,
                               kCGImagePropertyGPSAltitude: Double.nan])
        #expect(badAltitude == ImageInfo.GPS(latitude: 46, longitude: 8, altitude: nil))
    }

    @Test func descriptionMergesSourcesOnce() {
        let xmp = CGImageMetadataCreateMutable()
        #expect(CGImageMetadataSetValueWithPath(xmp, nil, "dc:creator" as CFString, ["A"] as CFArray))
        let d = pure([
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCByline: ["B"]] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "C"] as [CFString: Any],
        ], metadata: xmp).description
        #expect(d.creator == "A")
        let withoutXMP = pure([
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCByline: ["B"]] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "C"] as [CFString: Any],
        ]).description
        #expect(withoutXMP.creator == "B")
        #expect(pure([kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "C"] as [CFString: Any]])
            .description.creator == "C")
    }

    @Test func keywordsCapped() {
        let words = (0..<10_000).map { "k\($0)" }
        let d = pure([kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: words] as [CFString: Any]]).description
        #expect(d.keywords == Array(words.prefix(50)))
        #expect(d.moreKeywords)
        let fifty = Array(words.prefix(50))
        let exact = pure([kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: fifty] as [CFString: Any]]).description
        #expect(exact.keywords == fifty)
        #expect(!exact.moreKeywords)
    }

    // Both dates come from the file a symlink points to, as Modified always did.
    @Test func datesFollowSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("t.jpg"), width: 8, height: 8)
        let old = Date(timeIntervalSince1970: 946_684_800)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: target.path)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let info = ImageInfo.read(link)
        let expected = old.formatted(date: .abbreviated, time: .shortened)
        #expect(info.modified == expected)
        #expect(info.created == expected)
    }

    @Test func missingValuesLeftOut() throws {
        let info = try info([:], type: .png, name: "a.png")
        #expect(info.camera == nil)
        #expect(info.lens == nil)
        #expect(info.taken == nil)
        #expect(info.gps == nil)
        #expect(info.exposure == ImageInfo.Exposure())
        #expect(info.fileName == "a.png")
        #expect(info.formatLine.hasPrefix("PNG · 8 × 8 · "))
    }

    // xmp:Rating is free text from the file: out-of-range numbers must not trap.
    @Test func badXMPRatingIsDropped() {
        func rating(_ text: String) -> Int? {
            let xmp = CGImageMetadataCreateMutable()
            #expect(CGImageMetadataSetValueWithPath(xmp, nil, "xmp:Rating" as CFString, text as CFString))
            return pure([:], metadata: xmp).description.rating
        }
        #expect(rating("1e30") == nil)
        #expect(rating("nan") == nil)
        #expect(rating("inf") == nil)
        #expect(rating("-1") == nil)
        #expect(rating("4") == 4)
        #expect(rating("4.0") == 4)
    }

    // The summary takes the depth as a number, never back from the translated "8 bits per channel".
    @Test func hdrSummaryKeepsTheBitDepth() {
        let props: [CFString: Any] = [kCGImagePropertyDepth: 8, kCGImagePropertyProfileName: "Display P3"]
        let picture = ImageInfo.read(properties: props, metadata: nil, url: URL(fileURLWithPath: "/tmp/a.heic"),
                                     fileSize: nil, headroom: 4).picture
        #expect(picture.summary == "P3 · 8-bit · HDR")
        #expect(picture.headroom == 4)
        #expect(picture.hdr == "Gain map, up to 4×")
    }

    @Test func formatComesFromTheContents() throws {
        #expect(try info([:], type: .png, name: "photo.jpg").formatLine.hasPrefix("PNG · 8 × 8 · "))
        #expect(try info([:], type: .png, name: "photo").formatLine.hasPrefix("PNG · 8 × 8 · "))
    }

    @Test func jpegCommentSegment() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("c.jpg"), width: 8, height: 8)
        var data = try Data(contentsOf: url)
        let text = Array("hello comment".utf8)
        data.insert(contentsOf: [0xFF, 0xFE, 0, UInt8(text.count + 2)] + text, at: 2)
        try data.write(to: url)
        #expect(ImageInfo.read(url).description.comment == "hello comment")
        #expect(try info([:]).description.comment == nil)
    }

    // EXIF numbers are file data, and ImageIO copies XMP values in unchecked: absurd ones must not trap.
    @Test func absurdExposureNumbersAreDropped() {
        func e(_ values: [CFString: Any]) -> ImageInfo.Exposure { pure([kCGImagePropertyExifDictionary: values]).exposure }
        #expect(e([kCGImagePropertyExifFocalLength: 9.223372036854776e18]).focal == nil)
        #expect(e([kCGImagePropertyExifFocalLength: Double.nan]).focal == nil)
        #expect(e([kCGImagePropertyExifExposureTime: 1.084202172485504e-19]).shutter == nil)
        #expect(e([kCGImagePropertyExifExposureTime: 5e-324]).shutter == nil)
    }

    @Test func jpegCommentAfterLargeSegmentsAndOnlyForJPEG() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("c.jpg"), width: 8, height: 8)
        var data = try Data(contentsOf: url)
        let text = Array("late comment".utf8)
        let app = [UInt8](repeating: 0x41, count: 65_533)
        let filler: [UInt8] = (0..<8).flatMap { _ in [0xFF, 0xE9, 0xFF, 0xFF] + app }  // 8 × 64 KB APP9 segments
        data.insert(contentsOf: filler + [0xFF, 0xFE, 0, UInt8(text.count + 2)] + text, at: 2)
        try data.write(to: url)
        #expect(ImageInfo.read(url).description.comment == "late comment")
        try data.prefix(100_000).write(to: url)  // cut inside the segments
        #expect(ImageInfo.jpegComment(url) == nil)
        #expect(try info([:], type: .png, name: "p.png").description.comment == nil)
    }

    @Test func coordinateText() {
        #expect(InfoText.latitude(-33.8688) == "33.8688° S")
        #expect(InfoText.latitude(46.6356) == "46.6356° N")
        #expect(InfoText.longitude(-160) == "160.0000° W")
        #expect(InfoText.longitude(8.5939) == "8.5939° E")
        #expect(InfoText.altitude(1447) == "1,447 m")
    }

    @Test func stars() {
        #expect(InfoText.stars(4) == "★★★★☆")
    }

    // Moved from MetadataReaderTests.

    @Test func cameraDoesNotRepeatTheMake() {
        #expect(MetadataReader.camera(make: "Canon", model: "Canon EOS R6") == "Canon EOS R6")
        #expect(MetadataReader.camera(make: "Canon ", model: "EOS R6") == "Canon EOS R6")
        #expect(MetadataReader.camera(make: "NIKON CORPORATION", model: "NIKON D850") == "NIKON D850")
        #expect(MetadataReader.camera(make: "Apple", model: "iPhone 15 Pro") == "Apple iPhone 15 Pro")
        #expect(MetadataReader.camera(make: "   ", model: "X100") == "X100")
        #expect(MetadataReader.camera(make: "", model: "X100") == "X100")
        #expect(MetadataReader.camera(make: "FUJIFILM", model: nil) == "FUJIFILM")
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R6"]
        #expect(pure([kCGImagePropertyTIFFDictionary: tiff]).camera == "Canon EOS R6")
    }

    @Test func formatsExposureTimes() {
        let decimal = { (x: Double) in
            Measurement(value: x, unit: UnitDuration.seconds).formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        #expect(MetadataReader.exposure(0.004) == "1/250 s")
        #expect(MetadataReader.exposure(1.0 / 3) == "1/3 s")
        #expect(MetadataReader.exposure(0.5) == "1/2 s")
        #expect(MetadataReader.exposure(0.8) == decimal(0.8))
        #expect(MetadataReader.exposure(0.6) == decimal(0.6))
        #expect(MetadataReader.exposure(1) == decimal(1))
        #expect(MetadataReader.exposure(2.5) == decimal(2.5))
        func shutter(_ s: Double) -> String? {
            pure([kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: s] as [CFString: Any]]).exposure.shutter
        }
        #expect(shutter(0.004) == "1/250")
        #expect(shutter(1.0 / 3) == "1/3")
        #expect(shutter(0.8) == "0.8")
        #expect(shutter(2) == "2")
    }

    @Test func formatsDateTakenWithTheSystemFormatter() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 18, minute: 32, second: 5))!
        #expect(MetadataReader.taken("2026:08:14 18:32:05") == date.formatted(date: .abbreviated, time: .shortened))
        #expect(MetadataReader.taken("0000:00:00 00:00:00") == nil)  // cameras without a clock write this
        #expect(MetadataReader.taken("garbage") == nil)
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:08:14 18:32:05"]
        #expect(pure([kCGImagePropertyExifDictionary: exif]).taken == date.formatted(date: .abbreviated, time: .shortened))
    }

    @Test func dateTakenPrefersExif() throws {
        let dir = try Fixtures.makeTempDir()
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:03:05 14:30:00"] as [CFString: Any],
        ]
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: exif)
        let local = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 14, minute: 30))
        #expect(MetadataReader.dateTaken(of: url) == local)
    }

    @Test func dateTakenFallsBackToModificationDate() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.png"), width: 8, height: 8, type: .png)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        #expect(MetadataReader.dateTaken(of: url) == modified)
        #expect(MetadataReader.dateTaken(of: dir.appendingPathComponent("missing.jpg")) == nil)
    }
}
