import Foundation
import ImageIO

public enum MetadataReader {
    /// Model alone when it already names the maker ("Canon" + "Canon EOS R6" -> "Canon EOS R6").
    static func camera(make: String?, model: String?) -> String {
        let make = make?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        let brand = make.split(separator: " ").first.map(String.init) ?? ""
        if make.isEmpty || model.lowercased().hasPrefix(brand.lowercased()) { return model }
        return model.isEmpty ? make : "\(make) \(model)"
    }

    /// EXIF stores local wall time as "yyyy:MM:dd HH:mm:ss" (Gregorian, no time zone); shown in the
    /// system's date format. nil for placeholders like "0000:00:00 00:00:00".
    static func taken(_ exif: String) -> String? {
        exifDate(exif)?.formatted(date: .abbreviated, time: .shortened)
    }

    /// EXIF "yyyy:MM:dd HH:mm:ss" as a date in the local calendar; nil for placeholders.
    static func exifDate(_ exif: String) -> Date? {
        let n = exif.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard n.count == 6, n[0] > 0, (1...12).contains(n[1]), (1...31).contains(n[2]) else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(
            year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4], second: n[5]))
    }

    /// EXIF DateTimeOriginal as a local date, else the file's modification date, else nil.
    public static func dateTaken(of url: URL) -> Date? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let date = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(exifDate) {
            return date
        }
        return url.modificationDate
    }

    /// 1/N for fast shutters and exact unit fractions (1/2, 1/3); decimal seconds otherwise (0.8 s, 2 s).
    static func exposure(_ seconds: Double) -> String {
        let reciprocal = 1 / seconds
        let n = reciprocal.rounded()
        if n >= 2, seconds <= 0.25 || abs(reciprocal - n) < 0.01 {
            return String(localized: "1/\(Int(n)) s", comment: "exposure time, a fraction of a second")
        }
        return Measurement(value: seconds, unit: UnitDuration.seconds).formatted(.measurement(
            width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    /// A file size the way Finder shows it.
    public static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
