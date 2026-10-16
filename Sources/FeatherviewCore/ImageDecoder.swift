import CoreGraphics
import Foundation
import ImageIO

public enum DecodeError: Error, Equatable {
    case unreadable(URL)
}

public enum ImageDecoder {
    /// Pixel size as displayed, with EXIF orientation applied. nil if the file isn't a readable image.
    public static func displaySize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Decodes upright, downsampled so the longest side is at most `maxPixelSize` (nil = full size).
    /// Never upscales. Pixels are decoded here, not lazily at first draw, so callers can run this
    /// off the main thread and the UI never stalls on display.
    public static func decode(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let size = displaySize(of: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        let full = Int(max(size.width, size.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? full, full),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        return image
    }
}
