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

    /// The longest side to decode at: the smallest of full, ½, ¼, ⅛ that is still at least `target`.
    /// JPEG decodes those steps directly; any size in between costs a full decode plus a resample
    /// (12 MP to 3456 px: 100 ms instead of 40 ms). Images stay at most 2× the target per side.
    public static func decodeSize(full: Int, target: Int) -> Int {
        var size = full
        for shift in 1...3 {
            let step = (full + (1 << shift) - 1) >> shift
            guard step >= target else { break }
            size = step
        }
        return size
    }

    /// Decodes upright, downsampled so the longest side is at most `maxPixelSize` (nil = full size),
    /// or with `halvingSteps` to the faster step at or above it (see `decodeSize`), for display.
    /// Never upscales. Pixels are decoded here, not lazily at first draw, so callers can run this
    /// off the main thread and the UI never stalls on display.
    public static func decode(_ url: URL, maxPixelSize: Int? = nil, halvingSteps: Bool = false) throws -> CGImage {
        guard let size = displaySize(of: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        let full = Int(max(size.width, size.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: halvingSteps
                ? decodeSize(full: full, target: maxPixelSize ?? full)
                : min(maxPixelSize ?? full, full),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        return image
    }
}
