import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Everything the info panel shows, read from the file and formatted (spec "Info panel").
/// Missing values stay nil, so the panel leaves their rows out.
public struct ImageInfo: Equatable, Sendable {
    public struct Exposure: Equatable, Sendable {
        /// Bare numbers for the tiles: "1/250", "8", "100", "35".
        public var shutter, aperture, iso, focal: String?
        /// "53 mm", only when it differs from the focal length.
        public var focal35: String?
        public var bias: String?
        public var flash: String?
        public var whiteBalance: String?
        public var metering: String?
    }

    public struct Picture: Equatable, Sendable {
        /// "3,000 × 2,000 · 6.0 MP"
        public var dimensions: String?
        public var profile: String?
        public var bitDepth: String?
        public var hdr: String?
        public var software: String?
        /// "P3 · 8-bit · HDR"
        public var summary: String?
        /// Gain map headroom, nil for SDR.
        public var headroom: Double?
    }

    public struct GPS: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var altitude: Double?
    }

    public struct Description: Equatable, Sendable {
        public var title, caption, creator, copyright, comment: String?
        public var keywords: [String] = []
        /// The file has more keywords than `keywords` holds; the panel ends the list in "…".
        public var moreKeywords = false
        public var rating: Int?
    }

    public var fileName: String
    /// "JPEG · 3,000 × 2,000 · 476 KB"
    public var formatLine: String
    public var camera: String?
    public var lens: String?
    public var taken: String?
    public var exposure = Exposure()
    public var picture = Picture()
    public var gps: GPS?
    public var description = Description()
    public var folder: String
    public var modified: String?
    public var created: String?

    /// The panel shows at most this many keywords.
    static let keywordLimit = 50

    public static func read(_ url: URL) -> ImageInfo {
        let fileSize = url.fileSize
        if OwnDecoders.format(for: url) != nil {  // ImageIO can't read it; own decoders give dimensions only
            let props: [CFString: Any] = ImageDecoder.displaySize(of: url).map {
                [kCGImagePropertyPixelWidth: Int($0.width), kCGImagePropertyPixelHeight: Int($0.height)]
            } ?? [:]
            return read(properties: props, metadata: nil, url: url, fileSize: fileSize)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return read(properties: [:], metadata: nil, url: url, fileSize: fileSize)
        }
        let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        var info = read(properties: CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:],
                        metadata: CGImageSourceCopyMetadataAtIndex(source, 0, nil), url: url, fileSize: fileSize,
                        type: type, headroom: gainMapHeadroom(source))
        if info.description.comment == nil, type == .jpeg { info.description.comment = jpegComment(url) }
        return info
    }

    /// Pure mapping from ImageIO properties and XMP metadata. `type` is the file's real format (else the
    /// extension's), `headroom` the gain map's.
    public static func read(properties props: [CFString: Any], metadata: CGImageMetadata?, url: URL,
                            fileSize: Int?, type: UTType? = nil, headroom: Double? = nil) -> ImageInfo {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]

        var dimensions: String?
        var picture = Picture()
        if let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int {
            let turned = (props[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
            let (w, h) = turned ? (height, width) : (width, height)
            dimensions = "\(w.formatted()) × \(h.formatted())"
            let megapixels = (Double(w * h) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
            picture.dimensions = String(localized: "\(dimensions!) · \(megapixels) MP", comment: "Info panel, dimensions and megapixels")
        }
        let format = (type ?? UTType(filenameExtension: url.pathExtension))?.preferredFilenameExtension ?? url.pathExtension
        let formatLine = [format.isEmpty ? nil : format.uppercased(), dimensions, fileSize.map(MetadataReader.format(bytes:))]
            .compactMap { $0 }.joined(separator: " · ")

        picture.profile = nonEmpty(props[kCGImagePropertyProfileName] as? String)
        let depth = props[kCGImagePropertyDepth] as? Int
        picture.bitDepth = depth.map { String(localized: "\($0) bits per channel", comment: "Info panel") }
        picture.software = nonEmpty(tiff[kCGImagePropertyTIFFSoftware] as? String)
        if let headroom {
            picture.headroom = headroom
            let times = headroom.formatted(.number.precision(.fractionLength(0...1)))
            picture.hdr = String(localized: "Gain map, up to \(times)×", comment: "Info panel")
        }
        picture.summary = summary(picture, depth: depth)

        var info = ImageInfo(fileName: url.lastPathComponent, formatLine: formatLine,
                             folder: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
        info.picture = picture
        info.camera = nonEmpty(MetadataReader.camera(make: tiff[kCGImagePropertyTIFFMake] as? String,
                                                     model: tiff[kCGImagePropertyTIFFModel] as? String))
        info.lens = nonEmpty(exif[kCGImagePropertyExifLensModel] as? String)
        info.taken = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(MetadataReader.taken)
        info.exposure = exposure(exif)
        info.gps = gps(props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:])

        func xmp(_ path: String) -> [String] { strings(metadata, path) }
        func first(_ sources: [String]...) -> String? { sources.lazy.compactMap { $0.first }.first }
        info.description.title = first(xmp("dc:title"), texts(iptc[kCGImagePropertyIPTCObjectName]))
        info.description.caption = first(xmp("dc:description"), texts(iptc[kCGImagePropertyIPTCCaptionAbstract]),
                                         texts(tiff[kCGImagePropertyTIFFImageDescription]))
        info.description.creator = first(xmp("dc:creator"), texts(iptc[kCGImagePropertyIPTCByline]),
                                         texts(tiff[kCGImagePropertyTIFFArtist]))
        info.description.copyright = first(xmp("dc:rights"), texts(iptc[kCGImagePropertyIPTCCopyrightNotice]),
                                           texts(tiff[kCGImagePropertyTIFFCopyright]))
        info.description.comment = first(texts(exif[kCGImagePropertyExifUserComment]), texts(png[kCGImagePropertyPNGComment]))
        let xmpKeywords = xmp("dc:subject")
        let keywords = xmpKeywords.isEmpty ? texts(iptc[kCGImagePropertyIPTCKeywords]) : xmpKeywords
        info.description.keywords = Array(keywords.prefix(keywordLimit))
        info.description.moreKeywords = keywords.count > keywordLimit
        let rating = xmp("xmp:Rating").first.flatMap { Double($0) }.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
            ?? (iptc[kCGImagePropertyIPTCStarRating] as? Int)
        info.description.rating = rating.flatMap { (1...5).contains($0) ? $0 : nil }

        let dates = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.creationDateKey])  // as stat() for Modified
        info.modified = url.modificationDate?.formatted(date: .abbreviated, time: .shortened)
        info.created = dates?.creationDate?.formatted(date: .abbreviated, time: .shortened)
        return info
    }

    private static func exposure(_ exif: [CFString: Any]) -> Exposure {
        var e = Exposure()
        let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        // 0 is EXIF's "unknown"; values outside these ranges come from corrupt rationals. NaN fails every range.
        func plausible(_ key: CFString, _ range: ClosedRange<Double>) -> Double? {
            (exif[key] as? Double).flatMap { range.contains($0) ? $0 : nil }
        }
        if let seconds = plausible(kCGImagePropertyExifExposureTime, .leastNonzeroMagnitude...86_399) {
            let n = (1 / seconds).rounded()
            e.shutter = n >= 2 && (seconds <= 0.25 || abs(1 / seconds - n) < 0.01)
                ? Int(exactly: n).map { "1/\($0)" }  // nil past Int.max: a corrupt file, no row
                : seconds.formatted(oneDecimal)
        }
        e.aperture = plausible(kCGImagePropertyExifFNumber, 0.5...128)?.formatted(oneDecimal)
        e.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first.flatMap { (1...10_000_000).contains($0) ? $0.formatted() : nil }
        let focal = plausible(kCGImagePropertyExifFocalLength, 0.5...10_000)?.rounded()
        e.focal = focal.flatMap { Int(exactly: $0) }?.formatted()
        if let focal35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, focal35 > 0, Double(focal35) != focal {
            e.focal35 = Measurement(value: Double(focal35), unit: UnitLength.millimeters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        if let bias = plausible(kCGImagePropertyExifExposureBiasValue, -20...20) {
            let number = bias.formatted(oneDecimal.sign(strategy: .always(includingZero: false)))
                .replacingOccurrences(of: "-", with: "−")
            e.bias = String(localized: "\(number) EV", comment: "Info panel, exposure bias")
        }
        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
            e.flash = flash & 1 == 1 ? String(localized: "Flash", comment: "Info panel, the flash fired")
                : String(localized: "No flash", comment: "Info panel")
        }
        switch exif[kCGImagePropertyExifWhiteBalance] as? Int {
        case 0: e.whiteBalance = String(localized: "Auto", comment: "Info panel, white balance")
        case 1: e.whiteBalance = lightSource(exif[kCGImagePropertyExifLightSource] as? Int)
            ?? String(localized: "Manual", comment: "Info panel, white balance")
        default: break
        }
        e.metering = switch exif[kCGImagePropertyExifMeteringMode] as? Int {
        case 1: String(localized: "Average", comment: "Info panel, metering mode")
        case 2: String(localized: "Centre-weighted", comment: "Info panel, metering mode")
        case 3: String(localized: "Spot", comment: "Info panel, metering mode")
        case 4: String(localized: "Multi-spot", comment: "Info panel, metering mode")
        case 5: String(localized: "Multi-segment", comment: "Info panel, metering mode")
        case 6: String(localized: "Partial", comment: "Info panel, metering mode")
        default: nil
        }
        return e
    }

    private static func lightSource(_ code: Int?) -> String? {
        switch code {
        case 1, 9: String(localized: "Daylight", comment: "Info panel, white balance")
        case 2: String(localized: "Fluorescent", comment: "Info panel, white balance")
        case 3: String(localized: "Tungsten", comment: "Info panel, white balance")
        case 4: String(localized: "Flash", comment: "Info panel, the flash fired")
        case 10: String(localized: "Cloudy", comment: "Info panel, white balance")
        case 11: String(localized: "Shade", comment: "Info panel, white balance")
        default: nil
        }
    }

    /// Signed degrees from the refs; nil when a half is missing or out of range (bad rationals in a corrupt file),
    /// or for 0, 0 written without a fix.
    private static func gps(_ gps: [CFString: Any]) -> GPS? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double, abs(lat) <= 90,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double, abs(lon) <= 180 else { return nil }  // NaN fails too
        var altitude = (gps[kCGImagePropertyGPSAltitude] as? Double).flatMap { $0.isFinite ? $0 : nil }
        if gps[kCGImagePropertyGPSAltitudeRef] as? Int == 1 { altitude = altitude.map { -$0 } }  // below sea level
        if lat == 0, lon == 0, altitude == nil, gps[kCGImagePropertyGPSDateStamp] == nil { return nil }
        return GPS(latitude: (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" ? -lat : lat,
                   longitude: (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" ? -lon : lon,
                   altitude: altitude)
    }

    private static func summary(_ p: Picture, depth: Int?) -> String? {
        let profile = p.profile.map { name in
            name.contains("P3") ? "P3" : name.hasPrefix("sRGB") ? "sRGB" : name.contains("Adobe RGB") ? "Adobe RGB" : name
        }
        let bits = depth.map { String(localized: "\($0)-bit", comment: "Info panel, bit depth in the Image summary") }
        let parts = [profile, bits, p.headroom == nil ? nil : "HDR"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The gain map's headroom (linear, 4 = two stops), nil without one.
    private static func gainMapHeadroom(_ source: CGImageSource) -> Double? {
        func value(_ type: CFString, _ path: String) -> Double? {
            let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) as? [CFString: Any]
            let metadata = info?[kCGImageAuxiliaryDataInfoMetadata].map { $0 as! CGImageMetadata }
            return strings(metadata, path).first.flatMap(Double.init)
        }
        if #available(macOS 15, *), let stops = value(kCGImageAuxiliaryDataTypeISOGainMap, "HDRToneMap:AlternateHeadroom") { return pow(2, stops) }
        // shortcut: Apple gain maps without HDRGainMapHeadroom (older iPhones keep it in the maker note) show as SDR,
        // read the maker note when users miss their HDR row.
        return value(kCGImageAuxiliaryDataTypeHDRGainMap, "HDRGainMap:HDRGainMapHeadroom")
    }

    /// The JPEG COM segment's text, which ImageIO leaves out. Reads segment headers only, up to the scan, with plain
    /// reads: a mapped file that shrinks or vanishes (a network volume, a rewrite) would crash with SIGBUS.
    static func jpegComment(_ url: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        func read(_ count: Int) -> [UInt8]? {
            guard let data = try? file.read(upToCount: count), data.count == count else { return nil }
            return [UInt8](data)
        }
        guard read(2) == [0xFF, 0xD8] else { return nil }
        var offset: UInt64 = 2
        while (try? file.seek(toOffset: offset)) != nil, let header = read(4), header[0] == 0xFF {
            let marker = header[1]
            if marker == 0xFF { offset += 1; continue }  // fill byte
            if marker == 0xDA || marker == 0xD9 { return nil }
            let length = Int(header[2]) << 8 | Int(header[3])
            guard length >= 2 else { return nil }
            if marker == 0xFE {
                guard let text = read(length - 2) else { return nil }
                return nonEmpty((String(bytes: text, encoding: .utf8) ?? String(bytes: text, encoding: .isoLatin1))?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")))
            }
            offset += 2 + UInt64(length)
        }
        return nil
    }

    /// An XMP property's text: a simple value, or every item of an array (alt-text lists the default language first).
    private static func strings(_ metadata: CGImageMetadata?, _ path: String) -> [String] {
        guard let metadata, let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag) else { return [] }
        if let items = value as? [CGImageMetadataTag] {
            return items.compactMap { CGImageMetadataTagCopyValue($0).flatMap { nonEmpty("\($0)") } }
        }
        return nonEmpty("\(value)").map { [$0] } ?? []
    }

    /// A string or a list of strings from a property dictionary, empty ones left out.
    private static func texts(_ value: Any?) -> [String] {
        ((value as? [String]) ?? (value as? String).map { [$0] } ?? []).compactMap(nonEmpty)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

public enum InfoText {
    /// "46.6356° N"
    public static func latitude(_ v: Double) -> String {
        let n = abs(v).formatted(.number.precision(.fractionLength(4)))
        return v < 0 ? String(localized: "\(n)° S", comment: "Info panel, latitude south")
            : String(localized: "\(n)° N", comment: "Info panel, latitude north")
    }

    /// "160.0000° W"
    public static func longitude(_ v: Double) -> String {
        let n = abs(v).formatted(.number.precision(.fractionLength(4)))
        return v < 0 ? String(localized: "\(n)° W", comment: "Info panel, longitude west")
            : String(localized: "\(n)° E", comment: "Info panel, longitude east")
    }

    /// "1,447 m"
    public static func altitude(_ metres: Double) -> String {
        Measurement(value: metres.rounded(), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// "★★★★☆"
    public static func stars(_ rating: Int) -> String {
        let n = min(max(rating, 0), 5)
        return String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
    }
}
