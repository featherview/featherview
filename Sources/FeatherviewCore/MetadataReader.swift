import Foundation
import ImageIO

public struct MetadataField: Equatable, Sendable {
    public let label: String
    public let value: String
}

public enum MetadataReader {
    public static func fields(for url: URL) -> [MetadataField] {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
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
        add("Camera", [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " "))
        add("Lens", exif[kCGImagePropertyExifLensModel] as? String)
        add("Taken", exif[kCGImagePropertyExifDateTimeOriginal] as? String)
        if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
            add("Exposure", seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : "\(seconds) s")
        }
        add("Aperture", (exif[kCGImagePropertyExifFNumber] as? Double)
            .map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" })
        add("ISO", (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first.map(String.init))
        add("Focal length", (exif[kCGImagePropertyExifFocalLength] as? Double).map { "\(Int($0.rounded())) mm" })
        return out
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
