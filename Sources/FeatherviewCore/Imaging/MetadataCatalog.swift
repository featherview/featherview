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
    /// Internal entries left out: offsets, thumbnail data, maker notes.
    public var hiddenCount: Int

    public static func read(_ url: URL) -> MetadataCatalog {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              var props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return MetadataCatalog(sections: [], hiddenCount: 0) }
        guard let own = ownMetadata(url) else {
            props["{IPTC}"] = nil  // ImageIO makes it from the XMP; these containers have no IPTC of their own
            return make(properties: props, xmp: imageIOXMP(source))
        }
        props["{IPTC}"] = own.iptc.flatMap(iptc(records:))
        return make(properties: props, xmp: own.xmp.map(xmp(in:)) ?? [])
    }

    /// The picture's own XMP packet and IPTC records, read from where its container keeps them: a JPEG's
    /// segments before its image data (not a gain map's or a second image's), a TIFF's first directory,
    /// a PSD's image resources. Only these bytes are read. nil for other containers.
    static func ownMetadata(_ url: URL) -> (xmp: Data?, iptc: [UInt8]?)? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        let limit = 16 << 20  // shortcut: metadata over 16 MB is skipped, raise it if real files carry more
        func read(_ offset: Int, _ count: Int) -> [UInt8]? {
            guard offset >= 0, count > 0, count <= limit, (try? file.seek(toOffset: UInt64(offset))) != nil,
                  let data = try? file.read(upToCount: count), data.count == count else { return nil }
            return [UInt8](data)
        }
        guard let head = read(0, 8) else { return nil }
        if head[0] == 0xFF, head[1] == 0xD8 {
            var own: (xmp: Data?, iptc: [UInt8]?) = (nil, nil)
            var photoshop: [UInt8] = []  // image resources continue across APP13 segments
            let xmpSignature = Array("http://ns.adobe.com/xap/1.0/\0".utf8), psSignature = Array("Photoshop 3.0\0".utf8)
            var at = 2
            while let marker = read(at, 4), marker[0] == 0xFF, marker[1] != 0xDA, marker[1] != 0xD9 {
                if marker[1] == 0xFF { at += 1; continue }  // fill byte
                let length = Int(marker[2]) << 8 | Int(marker[3])
                guard length >= 2 else { break }
                if marker[1] == 0xE1 || marker[1] == 0xED, let body = read(at + 4, length - 2) {
                    if own.xmp == nil, body.starts(with: xmpSignature) { own.xmp = Data(body.dropFirst(xmpSignature.count)) }
                    if marker[1] == 0xED, body.starts(with: psSignature) { photoshop += body.dropFirst(psSignature.count) }
                }
                at += 2 + length
            }
            own.iptc = resource(0x0404, in: photoshop)
            return own
        }
        if head.starts(with: [0x49, 0x49, 42, 0]) || head.starts(with: [0x4D, 0x4D, 0, 42]) {
            let little = head[0] == 0x49
            func number(_ b: ArraySlice<UInt8>) -> Int {
                (little ? b.reversed() : Array(b)).reduce(0) { $0 << 8 | Int($1) }
            }
            let directory = number(head[4..<8])
            guard let count = read(directory, 2).map({ number($0[...]) }),
                  let entries = read(directory + 2, count * 12) else { return (nil, nil) }
            var tags: [Int: [UInt8]] = [:]
            for e in stride(from: 0, to: entries.count, by: 12) {
                let tag = number(entries[e..<e + 2]), type = number(entries[e + 2..<e + 4])
                guard [700, 33723, 34377].contains(tag) else { continue }
                let size = number(entries[e + 4..<e + 8]) * (type == 4 ? 4 : 1)  // LONG or bytes
                tags[tag] = size <= 4 ? Array(entries[e + 8..<e + 8 + max(size, 0)])
                    : read(number(entries[e + 8..<e + 12]), size)
            }
            return (tags[700].map { Data($0) }, tags[34377].flatMap { resource(0x0404, in: $0) } ?? tags[33723])
        }
        if head.starts(with: Array("8BPS".utf8)) {
            guard let modeLength = read(26, 4).map({ $0.reduce(0) { $0 << 8 | Int($1) } }),
                  let length = read(30 + modeLength, 4).map({ $0.reduce(0) { $0 << 8 | Int($1) } }),
                  let resources = read(34 + modeLength, length) else { return (nil, nil) }
            return (resource(0x0424, in: resources).map { Data($0) }, resource(0x0404, in: resources))
        }
        return nil
    }

    /// The body of Photoshop image resource `id` in a list of "8BIM" resources.
    static func resource(_ id: Int, in bytes: [UInt8]) -> [UInt8]? {
        func number(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        var i = 0
        while i + 12 <= bytes.count, bytes[i..<i + 4].elementsEqual("8BIM".utf8) {
            let found = Int(bytes[i + 4]) << 8 | Int(bytes[i + 5]) == id
            i += 6 + (Int(bytes[i + 6]) + 2) & ~1  // Pascal name, padded to even
            guard i + 4 <= bytes.count else { return nil }
            let size = number(i)
            i += 4
            guard size >= 0, i + size <= bytes.count else { return nil }
            if found { return Array(bytes[i..<i + size]) }
            i += (size + 1) & ~1
        }
        return nil
    }

    /// The XMP of containers ownMetadata doesn't read (HEIC, PNG, WebP, …), which have no IPTC for ImageIO
    /// to mirror into it. Only when the picture itself has a packet: an iPhone photo's belongs to its gain map.
    static func imageIOXMP(_ source: CGImageSource) -> [(String, String)] {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              CGImageMetadataCopyTagWithPath(metadata, nil, "iio:hasXMP" as CFString)
                  .flatMap({ CGImageMetadataTagCopyValue($0) as? String }) == "True" else { return [] }
        return tags(of: metadata, skipping: ["iio", "exif", "exifEX", "tiff"])  // ImageIO mirrors EXIF and TIFF here
    }

    /// The tags of an XMP packet.
    /// shortcut: extended XMP (more JPEG APP1 segments) isn't joined, add it if files show up.
    static func xmp(in packet: Data) -> [(String, String)] {
        let xml: Data
        if let start = find("<x:xmpmeta", in: packet), let end = find("</x:xmpmeta>", in: packet, from: start.upperBound) {
            xml = packet[start.lowerBound..<end.upperBound]
        } else if let start = find("<rdf:RDF", in: packet), let end = find("</rdf:RDF>", in: packet, from: start.upperBound) {
            // The x:xmpmeta wrapper is optional, but ImageIO only reads packets that have it.
            xml = Data(#"<x:xmpmeta xmlns:x="adobe:ns:meta/">"#.utf8) + packet[start.lowerBound..<end.upperBound]
                + Data("</x:xmpmeta>".utf8)
        } else { return [] }
        guard let metadata = CGImageMetadataCreateFromXMPData(xml as CFData) else { return [] }
        return tags(of: metadata, skipping: ["iio"])  // iio:hasXMP
    }

    static func tags(of metadata: CGImageMetadata, skipping prefixes: Set<String>) -> [(String, String)] {
        (CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []).compactMap { tag in
            guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?, !prefixes.contains(prefix),
                  let name = CGImageMetadataTagCopyName(tag) as String?,
                  let value = xmpValue(tag) else { return nil }
            return ("\(prefix):\(name)", value)
        }
    }

    /// IPTC records as ImageIO reads them on their own. ImageIO's merged "{IPTC}" fills in values from XMP and TIFF.
    static func iptc(records: [UInt8]) -> [String: Any]? {
        guard !records.isEmpty, blankJPEG.count > 2 else { return nil }
        // Standing alone in a small JPEG, the records have nothing for ImageIO to merge them with.
        let resources = Array("8BIM".utf8) + [4, 4, 0, 0]
            + [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: records.count >> $0) } + records
        var segments: [UInt8] = []
        for start in stride(from: 0, to: resources.count, by: 60_000) {  // APP13 segments of under 64 KB each
            let body = Array("Photoshop 3.0\0".utf8) + resources[start..<min(start + 60_000, resources.count)]
            segments += [0xFF, 0xED, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body
        }
        var jpeg = blankJPEG
        jpeg.insert(contentsOf: segments, at: 2)
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])?["{IPTC}"] as? [String: Any]
    }

    static let blankJPEG: Data = {
        let data = NSMutableData()
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    static func find(_ needle: String, in bytes: Data, from offset: Int = 0) -> Range<Int>? {
        let needle = Array(needle.utf8)
        guard offset < bytes.count else { return nil }
        return bytes.withUnsafeBytes { raw -> Range<Int>? in
            guard let base = raw.baseAddress,
                  let hit = memmem(base + offset, raw.count - offset, needle, needle.count) else { return nil }
            let at = base.distance(to: UnsafeRawPointer(hit))
            return at..<at + needle.count
        }
    }

    /// Groups ImageIO's property dictionaries ("{Exif}", "{GPS}", …) and XMP tags ("dc:title").
    static func make(properties: [String: Any], xmp: [(tag: String, value: String)]) -> MetadataCatalog {
        var hidden = 0
        var sections: [MetadataSection] = []
        for (key, value) in properties {
            guard key.hasPrefix("{"), let dictionary = value as? [String: Any] else { continue }
            if key.hasPrefix("{Maker") { hidden += dictionary.count; continue }  // maker notes, tags named by numbers
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

    /// "Exposure time (ExposureTime): 1/250 s", one entry per line; nil for no entries, so nothing is copied.
    public static func copyText(_ entries: [MetadataEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        return entries.map { "\($0.label) (\($0.tag)): \($0.value)" }.joined(separator: "\n")
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
