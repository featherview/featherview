import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DateTakenError: Error, Equatable {
    case unsupportedFormat, unreadable, writeFailed
}

/// The EXIF date taken ("yyyy:MM:dd HH:mm:ss", a wall time without zone): read, shift, and rewrite
/// losslessly (spec "Per-image operations").
public enum DateTaken {
    /// Formats whose date ImageIO changes without re-encoding (`public.heics` does not conform to `.heic`).
    static let supported: [UTType] = [.jpeg, .heic, .tiff, UTType("com.adobe.photoshop-image")!]

    static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// EXIF `DateTimeOriginal` as stored; nil when missing or a placeholder.
    public static func original(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return original(source)
    }

    static func original(_ source: CGImageSource) -> String? {
        guard let date = exifValue(source, kCGImagePropertyExifDateTimeOriginal),
              MetadataReader.exifDate(date) != nil else { return nil }
        return date
    }

    static func exifValue(_ source: CGImageSource, _ key: CFString) -> String? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (props?[kCGImagePropertyExifDictionary] as? [CFString: Any])?[key] as? String
    }

    /// The date taken, else the file's modification date as a wall time in the Mac's time zone.
    public static func current(of url: URL) -> String? {
        original(of: url) ?? fileDate(of: url)
    }

    /// The file's modification date as a wall time in the Mac's time zone.
    public static func fileDate(of url: URL) -> String? {
        guard let modified = url.modificationDate else { return nil }
        let local = Calendar(identifier: .gregorian)
        let parts = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: modified)
        return gmt.date(from: parts).map(exif)
    }

    /// A wall time held as a `Date` in GMT (what a date picker shows with its time zone set to GMT).
    public static func wallTime(_ exif: String) -> Date? {
        let n = exif.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard n.count == 6, n[0] > 0, (1...12).contains(n[1]), (1...31).contains(n[2]),
              (0...23).contains(n[3]), (0...59).contains(n[4]), (0...60).contains(n[5]) else { return nil }
        return gmt.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4], second: n[5]))
    }

    public static func exif(_ wallTime: Date) -> String {
        let c = gmt.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wallTime)
        return String(format: "%04d:%02d:%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    /// Plain wall-time arithmetic: no time zone, so no daylight-saving jumps.
    public static func shifted(_ exif: String, by seconds: Int) -> String? {
        guard let date = wallTime(exif)?.addingTimeInterval(TimeInterval(seconds)) else { return nil }
        let result = Self.exif(date)
        // EXIF holds years 0001–9999; a year past that, or a BC year printed without its era, doesn't read back.
        return result.count == 19 && wallTime(result) == date ? result : nil
    }

    /// The moment the wall time means, at EXIF `OffsetTimeOriginal` ("+02:00") or else in the Mac's time zone.
    public static func instant(_ exif: String, offset: String?) -> Date? {
        guard let wall = wallTime(exif) else { return nil }
        if let offset, let seconds = offsetSeconds(offset) { return wall.addingTimeInterval(-TimeInterval(seconds)) }
        let parts = gmt.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wall)
        return Calendar(identifier: .gregorian).date(from: parts)
    }

    static func offsetSeconds(_ offset: String) -> Int? {
        let sign: Int
        switch offset.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        let n = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard n.count == 2, (0...14).contains(n[0]), (0...59).contains(n[1]) else { return nil }
        return sign * (n[0] * 3600 + n[1] * 60)
    }

    /// The file's bytes with only the date changed; pixels and other metadata stay.
    /// shortcut: TIFF drops `OffsetTimeOriginal` and `SubsecTimeOriginal` (ImageIO), upgrade when ImageIO keeps them or someone asks.
    public static func rewritten(_ url: URL, date: String) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { throw DateTakenError.unreadable }
        // Content, not extension: a PNG named .jpg must still be refused.
        guard let type = UTType(sourceType as String), supported.contains(where: { type.conforms(to: $0) })
        else { throw DateTakenError.unsupportedFormat }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, sourceType, CGImageSourceGetCount(source), nil),
              CGImageDestinationCopyImageSource(dest, source, [kCGImageDestinationDateTime: date] as CFDictionary, nil)
        else { throw DateTakenError.unsupportedFormat }
        // Never claim a change that didn't happen.
        guard let written = CGImageSourceCreateWithData(data, nil),
              exifValue(written, kCGImagePropertyExifDateTimeOriginal) == date else { throw DateTakenError.unsupportedFormat }
        return data as Data
    }

    /// Changes the file in place: a temp file next to it, swapped in, then its file dates follow.
    /// A symlink's target is changed. Any failure leaves the original untouched.
    public static func apply(_ link: URL, date: String) throws {
        let url = link.resolvingSymlinksInPath()  // replaceItemAt can't swap a symlink
        let offset = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { exifValue($0, kCGImagePropertyExifOffsetTimeOriginal) }
        let data = try rewritten(url, date: date)
        let temp = ImageSaver.tempURL(in: url.deletingLastPathComponent(), ext: url.pathExtension)
        defer { try? FileManager.default.removeItem(at: temp) }  // no-op once swapped in
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch { throw DateTakenError.writeFailed }
        setFileDates(url, date: date, offset: offset)
    }

    /// One URL per file on disk, in order: `apply` changes a symlink's target, so a second link to it would shift it twice.
    public static func distinctFiles(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    /// Modified and created dates follow the date taken.
    public static func setFileDates(_ url: URL, date: String, offset: String?) {
        guard let instant = instant(date, offset: offset) else { return }
        try? FileManager.default.setAttributes([.creationDate: instant, .modificationDate: instant], ofItemAtPath: url.path)
    }
}
