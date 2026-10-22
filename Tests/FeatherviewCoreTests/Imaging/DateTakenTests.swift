import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct DateTakenTests {
    static let psd = UTType("com.adobe.photoshop-image")!
    static var exifDate: [CFString: Any] { [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05",
                                         kCGImagePropertyExifDateTimeDigitized: "2020:01:02 03:04:05"],
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.5, kCGImagePropertyGPSLatitudeRef: "N"],
    ] }

    func properties(_ data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    func exif(_ props: [CFString: Any]) -> [CFString: Any] { props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:] }

    func pixels(_ data: Data) -> RGBAImage? {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap { RGBAImage($0) }
    }

    @Test(arguments: [UTType.jpeg, .heic, .tiff, psd])
    func rewriteKeepsPixelsAndMetadata(_ type: UTType) throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.\(type.preferredFilenameExtension!)"),
                                          width: 16, height: 8, type: type, orientation: 6, properties: Self.exifDate)
        let before = try Data(contentsOf: url)
        let data = try DateTaken.rewritten(url, date: "2024:07:01 12:00:00")
        let props = properties(data)
        #expect(exif(props)[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:07:01 12:00:00")
        #expect(exif(props)[kCGImagePropertyExifDateTimeDigitized] as? String == "2024:07:01 12:00:00")
        #expect(props[kCGImagePropertyOrientation] as? Int == 6)
        #expect((props[kCGImagePropertyGPSDictionary] as? [CFString: Any])?[kCGImagePropertyGPSLatitude] as? Double == 48.5)
        #expect(pixels(data) != nil && pixels(data) == pixels(before))
    }

    @Test func rewriteCreatesMissingDate() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        #expect(DateTaken.original(of: url) == nil)
        let data = try DateTaken.rewritten(url, date: "2024:07:01 12:00:00")
        #expect(exif(properties(data))[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:07:01 12:00:00")
    }

    @Test func heicSequenceAndOthersRefused() throws {
        let dir = try Fixtures.makeTempDir()
        var urls = [
            try Fixtures.writeAPNG(to: dir.appendingPathComponent("a.png"), delays: [0.1, 0.1]),
            try Fixtures.writeHEICS(to: dir.appendingPathComponent("s.heics"), delays: [0.1, 0.1]),
        ]
        for type in [UTType.gif, .png, .bmp] {
            urls.append(try Fixtures.writeImage(to: dir.appendingPathComponent("b.\(type.preferredFilenameExtension!)"),
                                                width: 8, height: 8, type: type))
        }
        let avif = UTType("public.avif")!
        urls.append(try Fixtures.writeImage(to: dir.appendingPathComponent("c.avif"), width: 8, height: 8, type: avif))
        for url in urls {
            #expect(throws: DateTakenError.unsupportedFormat, "\(url.lastPathComponent)") {
                try DateTaken.rewritten(url, date: "2024:07:01 12:00:00")
            }
        }
    }

    @Test func pngNamedJpgRefused() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("p.jpg"), width: 8, height: 8, type: .png)
        #expect(throws: DateTakenError.unsupportedFormat) { try DateTaken.rewritten(url, date: "2024:07:01 12:00:00") }
    }

    @Test func unreadableRefused() throws {
        let dir = try Fixtures.makeTempDir()
        let url = dir.appendingPathComponent("missing.jpg")
        #expect(throws: DateTakenError.unreadable) { try DateTaken.rewritten(url, date: "2024:07:01 12:00:00") }
    }

    @Test func shiftIgnoresDaylightSaving() {
        // Wall-time arithmetic never sees a zone; Europe/Berlin jumps 02:00 → 03:00 that night.
        #expect(DateTaken.shifted("2026:03:29 01:30:00", by: 3600) == "2026:03:29 02:30:00")
    }

    @Test func shiftAcrossLeapDay() {
        #expect(DateTaken.shifted("2024:03:01 10:00:00", by: -86400) == "2024:02:29 10:00:00")
    }

    @Test func shiftAcrossYear() {
        #expect(DateTaken.shifted("2025:12:31 23:59:59", by: 1) == "2026:01:01 00:00:00")
    }

    @Test func shiftRefusesPlaceholders() {
        #expect(DateTaken.shifted("0000:00:00 00:00:00", by: 1) == nil)
        #expect(DateTaken.shifted("garbage", by: 1) == nil)
    }

    @Test func shiftRefusesDatesOutOfRange() {
        #expect(DateTaken.shifted("2024:05:01 12:00:00", by: .max) == nil)
        #expect(DateTaken.shifted("2024:05:01 12:00:00", by: .min) == nil)
        #expect(DateTaken.shifted("0001:01:01 00:00:00", by: -1) == nil)
        #expect(DateTaken.shifted("9999:12:31 23:59:59", by: 1) == nil)
    }

    @Test func wallTimeRoundTrips() throws {
        for s in ["2024:02:29 23:59:59", "1999:01:01 00:00:00", "2026:03:29 02:30:00"] {
            #expect(DateTaken.exif(try #require(DateTaken.wallTime(s))) == s)
        }
    }

    @Test func instantUsesOffset() throws {
        let instant = try #require(DateTaken.instant("2024:07:01 12:00:00", offset: "+02:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(instant == utc.date(from: DateComponents(year: 2024, month: 7, day: 1, hour: 10)))
        let west = try #require(DateTaken.instant("2024:07:01 12:00:00", offset: "-05:30"))
        #expect(west == utc.date(from: DateComponents(year: 2024, month: 7, day: 1, hour: 17, minute: 30)))
    }

    @Test func instantWithoutOffsetUsesLocalZone() throws {
        let instant = try #require(DateTaken.instant("2024:07:01 12:00:00", offset: nil))
        #expect(instant == Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 7, day: 1, hour: 12)))
    }

    @Test func currentFallsBackToFileDate() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let date = try #require(Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2023, month: 5, day: 6, hour: 7, minute: 8, second: 9)))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        #expect(DateTaken.current(of: url) == "2023:05:06 07:08:09")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(DateTaken.current(of: link) == "2023:05:06 07:08:09")  // the image's date, not the link's

        let dated = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8,
                                            properties: Self.exifDate)
        #expect(DateTaken.original(of: dated) == "2020:01:02 03:04:05")
        #expect(DateTaken.current(of: dated) == "2020:01:02 03:04:05")
    }

    @Test func originalRefusesTimesOutOfRange() throws {
        let dir = try Fixtures.makeTempDir()
        var props = Self.exifDate
        props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2020:01:01 24:00:00"]
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: props)
        // A date the shift can't read counts as none, so the grid shifts the others instead of copying it.
        #expect(DateTaken.original(of: url) == nil)
        #expect(DateTaken.current(of: url).flatMap(DateTaken.wallTime) != nil)
    }

    @Test func applyChangesInPlaceAndFileDates() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8,
                                          properties: Self.exifDate)
        try DateTaken.apply(url, date: "2024:07:01 12:00:00")
        #expect(DateTaken.original(of: url) == "2024:07:01 12:00:00")
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let instant = DateTaken.instant("2024:07:01 12:00:00", offset: nil)
        #expect(values.contentModificationDate == instant)
        #expect(values.creationDate == instant)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".featherview-") }
        #expect(leftovers.isEmpty)
    }

    @Test func applyUsesOffsetTimeOriginal() throws {
        let dir = try Fixtures.makeTempDir()
        var props = Self.exifDate
        props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05",
                                                 kCGImagePropertyExifOffsetTimeOriginal: "+02:00"]
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: props)
        try DateTaken.apply(url, date: "2024:07:01 12:00:00")
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        #expect(values.contentModificationDate == DateTaken.instant("2024:07:01 12:00:00", offset: "+02:00"))
    }

    @Test func unsupportedLeavesFileUntouched() throws {
        let dir = try Fixtures.makeTempDir()
        for type in [UTType.png, .gif] {
            let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.\(type.preferredFilenameExtension!)"),
                                              width: 8, height: 8, type: type)
            let bytes = try Data(contentsOf: url)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            #expect(throws: DateTakenError.self) { try DateTaken.apply(url, date: "2024:07:01 12:00:00") }
            #expect(try Data(contentsOf: url) == bytes)
            #expect(try URL(filePath: url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".featherview-") }
        #expect(leftovers.isEmpty)
    }

    @Test func readOnlyLeavesFileUntouched() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("ro.jpg"), width: 8, height: 8)
        let bytes = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(throws: DateTakenError.writeFailed) { try DateTaken.apply(url, date: "2024:07:01 12:00:00") }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func symlinkChangesTarget() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("t.jpg"), width: 8, height: 8)
        let link = dir.appendingPathComponent("l.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try DateTaken.apply(link, date: "2024:07:01 12:00:00")
        #expect(DateTaken.original(of: target) == "2024:07:01 12:00:00")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    }

    @Test func distinctFilesDropsLinksToTheSameFile() throws {
        let dir = try Fixtures.makeTempDir()
        let a = dir.appendingPathComponent("a.jpg"), c = dir.appendingPathComponent("c.jpg")
        try Data().write(to: a)
        try Data().write(to: c)
        let b = dir.appendingPathComponent("b.jpg"), d = dir.appendingPathComponent("d.jpg"), e = dir.appendingPathComponent("e.jpg")
        try FileManager.default.createSymbolicLink(at: b, withDestinationURL: a)
        try FileManager.default.createSymbolicLink(at: d, withDestinationURL: c)
        try FileManager.default.createSymbolicLink(at: e, withDestinationURL: c)
        #expect(DateTaken.distinctFiles([a, b, d, c, e]) == [a, d])
        #expect(DateTaken.distinctFiles([b, a]) == [b])
    }
}
