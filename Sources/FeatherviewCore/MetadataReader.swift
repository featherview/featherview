import Foundation
import ImageIO

public struct MetadataField: Equatable, Sendable {
    public let label: String
    public let value: String
}

public enum MetadataReader {
    public static func fields(for url: URL) -> [MetadataField] {
        // .fileSizeKey does not follow symlinks; resolve first so a link shows the image's size.
        let fileSize = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return fileSize.map { [MetadataField(label: "File size", value: format(bytes: $0))] } ?? [] }
        return fields(from: props, fileSize: fileSize)
    }

    /// Pure mapping from ImageIO properties. Missing values are left out, never shown as blanks.
    public static func fields(from props: [CFString: Any], fileSize: Int?) -> [MetadataField] {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var out: [MetadataField] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { out.append(MetadataField(label: label, value: value)) }
        }

        if let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            add("Dimensions", orientation >= 5 ? "\(height) × \(width)" : "\(width) × \(height)")
        }
        add("File size", fileSize.map(format(bytes:)))
        add("Camera", camera(make: tiff[kCGImagePropertyTIFFMake] as? String,
                             model: tiff[kCGImagePropertyTIFFModel] as? String))
        add("Lens", exif[kCGImagePropertyExifLensModel] as? String)
        add("Taken", exif[kCGImagePropertyExifDateTimeOriginal] as? String)
        if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
            add("Exposure", exposure(seconds))
        }
        add("Aperture", (exif[kCGImagePropertyExifFNumber] as? Double)
            .map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" })
        add("ISO", (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first.map(String.init))
        add("Focal length", (exif[kCGImagePropertyExifFocalLength] as? Double).map { "\(Int($0.rounded())) mm" })
        return out
    }

    /// Model alone when it already names the maker ("Canon" + "Canon EOS R6" -> "Canon EOS R6").
    static func camera(make: String?, model: String?) -> String {
        let make = make?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        let brand = make.split(separator: " ").first.map(String.init) ?? ""
        if make.isEmpty || model.lowercased().hasPrefix(brand.lowercased()) { return model }
        return model.isEmpty ? make : "\(make) \(model)"
    }

    /// 1/N for fast shutters and exact unit fractions (1/2, 1/3); decimal seconds otherwise (0.8 s, 2 s).
    static func exposure(_ seconds: Double) -> String {
        let reciprocal = 1 / seconds
        let n = reciprocal.rounded()
        if n >= 2, seconds <= 0.25 || abs(reciprocal - n) < 0.01 { return "1/\(Int(n)) s" }
        return "\(seconds.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
