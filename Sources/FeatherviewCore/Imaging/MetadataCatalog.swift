import Foundation
import ImageIO

public struct MetadataEntry: Equatable, Sendable, Identifiable {
    public var id: String  // "EXIF.ExposureTime"
    public var label: String
    public var tag: String
    public var value: String

    public init(id: String, label: String, tag: String, value: String) {
        self.id = id
        self.label = label
        self.tag = tag
        self.value = value
    }
}

public struct MetadataSection: Equatable, Sendable, Identifiable {
    public var id: String  // "EXIF", "GPS", "IPTC", "XMP", "TIFF", others as ImageIO names them
    public var entries: [MetadataEntry]
}

/// Every tag of a picture for the All Metadata window, grouped, labelled and formatted.
public struct MetadataCatalog: Equatable, Sendable {
    public var sections: [MetadataSection]
    /// Internal entries left out: offsets, thumbnail data, binary maker notes.
    public var hiddenCount: Int

    public static func read(_ url: URL) -> MetadataCatalog {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return MetadataCatalog(sections: [], hiddenCount: 0) }
        var xmp: [(String, String)] = []
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           CGImageMetadataCopyTagWithPath(metadata, nil, "iio:hasXMP" as CFString)
               .flatMap({ CGImageMetadataTagCopyValue($0) as? String }) == "True" {
            for tag in CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? [] {
                guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?,
                      let name = CGImageMetadataTagCopyName(tag) as String?,
                      // ImageIO mirrors EXIF and TIFF into these namespaces; their own sections show them.
                      !["iio", "exif", "exifEX", "tiff"].contains(prefix),
                      let value = xmpValue(tag) else { continue }
                xmp.append(("\(prefix):\(name)", value))
            }
        }
        return make(properties: props, xmp: xmp)
    }

    /// Groups ImageIO's property dictionaries ("{Exif}", "{GPS}", …) and XMP tags ("dc:title").
    static func make(properties: [String: Any], xmp: [(tag: String, value: String)]) -> MetadataCatalog {
        var hidden = 0
        var sections: [MetadataSection] = []
        for (key, value) in properties {
            guard key.hasPrefix("{"), let dictionary = value as? [String: Any] else { continue }
            let id = key == "{Exif}" ? "EXIF" : String(key.dropFirst().dropLast())
            var entries: [MetadataEntry] = []
            for (tag, raw) in dictionary {
                guard !isInternal(tag), let value = format(raw, tag: tag, in: dictionary) else { hidden += 1; continue }
                entries.append(MetadataEntry(id: "\(id).\(tag)", label: label(for: tag), tag: tag, value: value))
            }
            if !entries.isEmpty { sections.append(MetadataSection(id: id, entries: entries)) }
        }
        let xmpEntries = xmp.compactMap { tag, value -> MetadataEntry? in
            if isInternal(tag) { hidden += 1; return nil }
            return MetadataEntry(id: "XMP.\(tag)", label: label(for: tag), tag: tag, value: value)
        }
        if !xmpEntries.isEmpty { sections.append(MetadataSection(id: "XMP", entries: xmpEntries)) }

        let first = ["EXIF", "GPS", "IPTC", "XMP", "TIFF"]
        sections.sort { a, b in
            let (i, j) = (first.firstIndex(of: a.id) ?? first.count, first.firstIndex(of: b.id) ?? first.count)
            return i != j ? i < j : a.id.localizedStandardCompare(b.id) == .orderedAscending
        }
        for i in sections.indices {
            sections[i].entries.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        return MetadataCatalog(sections: sections, hiddenCount: hidden)
    }

    /// Sections with the entries whose label, tag or value contains `query`, ignoring case and diacritics.
    public func filtered(_ query: String) -> MetadataCatalog {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return self }
        func matches(_ text: String) -> Bool { text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let sections = sections.compactMap { section -> MetadataSection? in
            let entries = section.entries.filter { matches($0.label) || matches($0.tag) || matches($0.value) }
            return entries.isEmpty ? nil : MetadataSection(id: section.id, entries: entries)
        }
        return MetadataCatalog(sections: sections, hiddenCount: hiddenCount)
    }

    /// "Exposure time (ExposureTime): 1/250 s", one entry per line.
    public static func copyText(_ entries: [MetadataEntry]) -> String {
        entries.map { "\($0.label) (\($0.tag)): \($0.value)" }.joined(separator: "\n")
    }

    static func isInternal(_ tag: String) -> Bool {
        ["MakerNote", "JPEGInterchangeFormat", "JPEGInterchangeFormatLength", "StripOffsets", "StripByteCounts",
         "TileOffsets", "TileByteCounts", "FreeOffsets", "FreeByteCounts", "ExifOffset", "GPSInfo",
         "InteroperabilityOffset", "PrintImageMatching"].contains(tag)
            || tag.range(of: "Thumbnail", options: .caseInsensitive) != nil
    }

    /// nil for binary values, which are hidden.
    static func format(_ raw: Any, tag: String, in dictionary: [String: Any]) -> String? {
        switch (tag, raw) {
        case ("ExposureTime", let seconds as Double) where seconds > 0:
            return MetadataReader.exposure(seconds)
        case ("FNumber", let f as Double):
            return "f/\(f.formatted(.number.grouping(.never).precision(.fractionLength(0...1))))"
        case ("Latitude", let degrees as Double), ("Longitude", let degrees as Double):
            let ref = dictionary["\(tag)Ref"] as? String ?? ""
            let number = degrees.formatted(.number.grouping(.never).precision(.fractionLength(4)))
            return ref.isEmpty ? "\(number)°" : "\(number)° \(ref)"
        default:
            return plain(raw)
        }
    }

    static func plain(_ raw: Any) -> String? {
        switch raw {
        case is Data: return nil
        case let text as String: return text
        case let number as NSNumber:
            return number.doubleValue.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
        case let list as [Any]:
            let parts = list.map(plain)
            return parts.contains(nil) ? nil : parts.compactMap { $0 }.joined(separator: ", ")
        case let dictionary as [String: Any]:
            var parts: [String] = []
            for key in dictionary.keys.sorted() {
                guard let value = plain(dictionary[key]!) else { return nil }
                parts.append("\(key): \(value)")
            }
            return parts.joined(separator: "; ")
        default: return String(describing: raw)
        }
    }

    static func xmpValue(_ tag: CGImageMetadataTag) -> String? {
        let value = CGImageMetadataTagCopyValue(tag)
        switch CGImageMetadataTagGetType(tag) {
        case .alternateText:  // language alternatives: the first is x-default
            return (value as? [CGImageMetadataTag])?.first.flatMap(xmpValue)
        case .arrayOrdered, .arrayUnordered, .alternateArray:
            return (value as? [CGImageMetadataTag])?.compactMap(xmpValue).joined(separator: ", ")
        case .structure:
            guard let fields = value as? [String: CGImageMetadataTag] else { return nil }
            return fields.keys.sorted().compactMap { key in xmpValue(fields[key]!).map { "\(key): \($0)" } }
                .joined(separator: "; ")
        default:
            return value.map { "\($0)" }
        }
    }

    /// A readable name: from the table for common tags, else the tag split at its words ("FooBar" -> "Foo bar").
    static func label(for tag: String) -> String {
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        if let known = knownLabel(name) { return known }
        let chars = Array(name)
        var words: [String] = []
        for (i, c) in chars.enumerated() {
            let previous = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let starts = i == 0 || c.isUppercase && (previous?.isLowercase == true || previous?.isNumber == true
                || previous?.isUppercase == true && next?.isLowercase == true)
            if starts { words.append(String(c)) } else { words[words.count - 1].append(c) }
        }
        let readable = words.enumerated().map { i, word in
            word.allSatisfy(\.isUppercase) ? word : i == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
        }
        return readable.joined(separator: " ")
    }

    static func knownLabel(_ tag: String) -> String? {
        switch tag {
        // EXIF
        case "ExposureTime": String(localized: "Exposure time", comment: "Metadata tag name")
        case "FNumber": String(localized: "F-number", comment: "Metadata tag name")
        case "ExposureProgram": String(localized: "Exposure program", comment: "Metadata tag name")
        case "ISOSpeedRatings": String(localized: "ISO speed", comment: "Metadata tag name")
        case "ISOSpeed": String(localized: "ISO speed (EXIF 2.3)", comment: "Metadata tag name")
        case "DateTimeOriginal": String(localized: "Date taken", comment: "Metadata tag name")
        case "DateTimeDigitized": String(localized: "Date digitized", comment: "Metadata tag name")
        case "OffsetTime": String(localized: "Time zone", comment: "Metadata tag name")
        case "OffsetTimeOriginal": String(localized: "Time zone of date taken", comment: "Metadata tag name")
        case "OffsetTimeDigitized": String(localized: "Time zone of date digitized", comment: "Metadata tag name")
        case "ShutterSpeedValue": String(localized: "Shutter speed value", comment: "Metadata tag name")
        case "ApertureValue": String(localized: "Aperture value", comment: "Metadata tag name")
        case "BrightnessValue": String(localized: "Brightness", comment: "Metadata tag name")
        case "ExposureBiasValue": String(localized: "Exposure compensation", comment: "Metadata tag name")
        case "MaxApertureValue": String(localized: "Maximum aperture", comment: "Metadata tag name")
        case "MeteringMode": String(localized: "Metering mode", comment: "Metadata tag name")
        case "LightSource": String(localized: "Light source", comment: "Metadata tag name")
        case "Flash": String(localized: "Flash", comment: "Metadata tag name")
        case "FocalLength": String(localized: "Focal length", comment: "Metadata tag name")
        case "FocalLenIn35mmFilm": String(localized: "Focal length (35 mm)", comment: "Metadata tag name")
        case "ColorSpace": String(localized: "Color space", comment: "Metadata tag name")
        case "PixelXDimension": String(localized: "Width", comment: "Metadata tag name")
        case "PixelYDimension": String(localized: "Height", comment: "Metadata tag name")
        case "ExposureMode": String(localized: "Exposure mode", comment: "Metadata tag name")
        case "WhiteBalance": String(localized: "White balance", comment: "Metadata tag name")
        case "DigitalZoomRatio": String(localized: "Digital zoom", comment: "Metadata tag name")
        case "SceneCaptureType": String(localized: "Scene capture type", comment: "Metadata tag name")
        case "Contrast": String(localized: "Contrast", comment: "Metadata tag name")
        case "Saturation": String(localized: "Saturation", comment: "Metadata tag name")
        case "Sharpness": String(localized: "Sharpness", comment: "Metadata tag name")
        case "LensMake": String(localized: "Lens maker", comment: "Metadata tag name")
        case "LensModel": String(localized: "Lens model", comment: "Metadata tag name")
        case "LensSpecification": String(localized: "Lens specification", comment: "Metadata tag name")
        case "BodySerialNumber": String(localized: "Camera serial number", comment: "Metadata tag name")
        case "CameraOwnerName": String(localized: "Camera owner", comment: "Metadata tag name")
        case "ExifVersion": String(localized: "EXIF version", comment: "Metadata tag name")
        case "UserComment": String(localized: "Comment", comment: "Metadata tag name")
        // TIFF
        case "Make": String(localized: "Camera maker", comment: "Metadata tag name")
        case "Model": String(localized: "Camera model", comment: "Metadata tag name")
        case "Software": String(localized: "Software", comment: "Metadata tag name")
        case "DateTime": String(localized: "Date modified", comment: "Metadata tag name")
        case "Artist": String(localized: "Artist", comment: "Metadata tag name")
        case "Copyright": String(localized: "Copyright", comment: "Metadata tag name")
        case "ImageDescription": String(localized: "Description", comment: "Metadata tag name")
        case "Orientation": String(localized: "Orientation", comment: "Metadata tag name")
        case "XResolution": String(localized: "Horizontal resolution", comment: "Metadata tag name")
        case "YResolution": String(localized: "Vertical resolution", comment: "Metadata tag name")
        case "ResolutionUnit": String(localized: "Resolution unit", comment: "Metadata tag name")
        // GPS
        case "Latitude": String(localized: "Latitude", comment: "Metadata tag name")
        case "Longitude": String(localized: "Longitude", comment: "Metadata tag name")
        case "LatitudeRef": String(localized: "Latitude reference", comment: "Metadata tag name")
        case "LongitudeRef": String(localized: "Longitude reference", comment: "Metadata tag name")
        case "Altitude": String(localized: "Altitude", comment: "Metadata tag name")
        case "AltitudeRef": String(localized: "Altitude reference", comment: "Metadata tag name")
        case "TimeStamp": String(localized: "GPS time", comment: "Metadata tag name")
        case "DateStamp": String(localized: "GPS date", comment: "Metadata tag name")
        case "ImgDirection": String(localized: "Image direction", comment: "Metadata tag name")
        case "HPositioningError": String(localized: "Horizontal accuracy", comment: "Metadata tag name")
        // IPTC and XMP
        case "Keywords": String(localized: "Keywords", comment: "Metadata tag name")
        case "Byline": String(localized: "Author", comment: "Metadata tag name")
        case "CopyrightNotice": String(localized: "Copyright notice", comment: "Metadata tag name")
        case "Caption/Abstract": String(localized: "Caption", comment: "Metadata tag name")
        case "ObjectName": String(localized: "Title", comment: "Metadata tag name")
        case "Headline": String(localized: "Headline", comment: "Metadata tag name")
        case "City": String(localized: "City", comment: "Metadata tag name")
        case "Province/State": String(localized: "State or province", comment: "Metadata tag name")
        case "Country/PrimaryLocationName": String(localized: "Country", comment: "Metadata tag name")
        case "Rating": String(localized: "Rating", comment: "Metadata tag name")
        default: nil
        }
    }
}
