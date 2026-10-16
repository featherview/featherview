import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DecodeError: Error, Equatable {
    case unreadable(URL)
}

public enum ImageDecoder {
    /// Pages of a multi-page TIFF; 1 for every other file, so GIF frames and HEIC image sequences
    /// are not browsed as pages (spec: GIF shows its first frame).
    public static func pageCount(of url: URL) -> Int {
        if let own = OwnDecoders.format(for: url) {
            return (try? Data(contentsOf: url, options: .mappedIfSafe)).map { max(own.pageCount($0), 1) } ?? 1
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .tiff) == true else { return 1 }
        return max(CGImageSourceGetCount(source), 1)
    }

    /// Pixel size as displayed, with EXIF orientation applied. nil if the file isn't a readable image.
    public static func displaySize(of url: URL, page: Int = 0) -> CGSize? {
        if let own = OwnDecoders.format(for: url) {
            // Mapped, so only the header's pages are read from disk.
            return (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap { own.size($0, page) }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, page, nil) as? [CFString: Any],
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
    /// `page` is a page of a multi-page TIFF (see `pageCount`).
    public static func decode(_ url: URL, maxPixelSize: Int? = nil, halvingSteps: Bool = false, page: Int = 0) throws -> CGImage {
        if let own = OwnDecoders.format(for: url) {
            do {
                let image = try own.decode(try Data(contentsOf: url, options: .mappedIfSafe), page, maxPixelSize)
                return maxPixelSize.flatMap { scaled(image, longestSide: $0) } ?? image
            } catch {
                throw DecodeError.unreadable(url)
            }
        }
        guard let size = displaySize(of: url, page: page),
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
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, page, options as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        return image
    }

    /// `image` shrunk so its longest side is `longestSide`; nil if it's already that small.
    /// Our own decoders return full size; this brings them to the size ImageIO's would have.
    static func scaled(_ image: CGImage, longestSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longestSide > 0, longest > longestSide else { return nil }
        let scale = Double(longestSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
