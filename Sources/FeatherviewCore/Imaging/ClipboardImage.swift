import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ⌘C's pasteboard data, encoded off the main thread.
public enum ClipboardImage {
    /// PNG, not NSImage's uncompressed TIFF: the pasteboard refuses data above ~256 MB (≈64 MP RGBA as TIFF).
    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Pasted image data: page 0, full size, upright. Nil for empty or undecodable data.
    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The first pasteboard type ImageIO decodes, in the clipboard's order (its producer's preference).
    public static func preferredType(_ types: [String]) -> String? {
        types.first { id in
            guard let type = UTType(id), type.conforms(to: .image) else { return false }
            return ImageFormats.decodable.contains { type.conforms(to: $0) }
        }
    }
}
