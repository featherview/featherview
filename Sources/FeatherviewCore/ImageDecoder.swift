import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DecodeError: Error, Equatable {
    case unreadable(URL)
}

/// A screen's size in pixels (points × backing scale).
public struct PixelSize: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ImageDecoder {
    /// HDR display needs macOS 15 (spec "Formats").
    public static var supportsHDR: Bool { if #available(macOS 15, *) { true } else { false } }

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

    /// The longest side to decode an image of `image` (displayed size, orientation applied) at, so it
    /// fits any of `screens` without enlarging: the smallest halving step at or above that size.
    /// Integer arithmetic: a 3024×4032 portrait on a 2016 px high screen needs exactly 2016, and
    /// Double can give 2016.0000001, which picks full size.
    public static func fitDecodeSize(image: PixelSize, screens: [PixelSize]) -> Int {
        let longest = max(image.width, image.height)
        guard image.width > 0, image.height > 0 else { return longest }
        func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
        let needed = screens.map {
            min(ceilDiv(longest * $0.width, image.width), ceilDiv(longest * $0.height, image.height))
        }.max() ?? longest
        return decodeSize(full: longest, target: needed)
    }

    /// Decodes upright, downsampled so the longest side is at most `maxPixelSize` (nil = full size),
    /// or with `halvingSteps` to the faster step at or above it (see `decodeSize`), for display.
    /// Never upscales. Pixels are decoded here, not lazily at first draw, so callers can run this
    /// off the main thread and the UI never stalls on display.
    /// `screens`, in place of `maxPixelSize`: decode at `fitDecodeSize` for them (the viewer's fit mode).
    /// `page` is a page of a multi-page TIFF (see `pageCount`).
    /// Display decodes (`halvingSteps`) come back at 8 bits, or with `hdr` an HDR image at up to 16
    /// bits with its extra range; other decodes keep the file's depth.
    /// Ignored before macOS 15 (`supportsHDR`) and for own formats.
    /// `colorSpace` (the screen's) applies to 8-bit display decodes: Core Animation would otherwise
    /// convert each image on the main thread when it's first shown (≈18 ms for 12 MP).
    public static func decode(_ url: URL, maxPixelSize: Int? = nil, halvingSteps: Bool = false,
                              fitting screens: [PixelSize]? = nil, page: Int = 0,
                              hdr: Bool = false, colorSpace: CGColorSpace? = nil) throws -> CGImage {
        let image = try decodeFile(url, maxPixelSize: maxPixelSize, halvingSteps: halvingSteps, screens: screens,
                                   page: page, hdr: hdr)
        guard halvingSteps, let colorSpace, image.bitsPerComponent == 8, image.colorSpace != colorSpace else { return image }
        return redrawn(image, width: image.width, height: image.height, in: colorSpace) ?? image
    }

    private static func decodeFile(_ url: URL, maxPixelSize: Int?, halvingSteps: Bool, screens: [PixelSize]?,
                                   page: Int, hdr: Bool) throws -> CGImage {
        func fit(_ size: CGSize) -> Int? {
            screens.map { fitDecodeSize(image: PixelSize(width: Int(size.width), height: Int(size.height)), screens: $0) }
        }
        if let own = OwnDecoders.format(for: url) {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let limit = own.size(data, page).flatMap(fit) ?? maxPixelSize
                let image = try own.decode(data, page, limit)
                return limit.flatMap { scaled(image, longestSide: $0) } ?? image
            } catch {
                throw DecodeError.unreadable(url)
            }
        }
        guard let size = displaySize(of: url, page: page),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        let full = Int(max(size.width, size.height))
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: fit(size) ?? (halvingSteps
                ? decodeSize(full: full, target: maxPixelSize ?? full)
                : min(maxPixelSize ?? full, full)),
        ]
        let wantsHDR = hdr && supportsHDR
        if wantsHDR { options[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, page, options as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        // Display decodes only: batch and Save As keep every bit the file has.
        guard halvingSteps, image.bitsPerComponent > 8 else { return image }
        if wantsHDR, isHDR(image.colorSpace, type: CGImageSourceGetType(source)) {
            // ImageIO gives EXR as 32-bit float; the spec budgets HDR at 16 bits (twice SDR).
            guard image.bitsPerComponent > 16, let space = image.colorSpace, space.model == .rgb else { return image }
            guard let half = redrawn(image, width: image.width, height: image.height, in: space, bitsPerComponent: 16)
            else { throw DecodeError.unreadable(url) }
            return half
        }
        // 16-bit PNG/TIFF, float TIFF and EXR decode deep even as SDR; callers treat > 8 bits as HDR
        // and the cache budget assumes 8.
        guard let eight = redrawn(image, width: image.width, height: image.height,
                                  in: image.colorSpace.flatMap(sdrSpace) ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        else { throw DecodeError.unreadable(url) }
        return eight
    }

    /// PQ/HLG (HDR photos, gain maps), or extended range from a format made for HDR. ImageIO gives
    /// float TIFFs extended range even when every pixel is SDR, so those count as SDR.
    /// shortcut: a float TIFF with real highlights shows clipped, scan its pixels if anyone has such files.
    private static func isHDR(_ space: CGColorSpace?, type: CFString?) -> Bool {
        guard let space else { return false }
        if CGColorSpaceUsesITUR_2100TF(space) { return true }
        let hdrFormats = ["com.ilm.openexr-image", "public.radiance"].compactMap { UTType($0) }
        return CGColorSpaceUsesExtendedRange(space)
            && type.flatMap { UTType($0 as String) }.map { t in hdrFormats.contains { t.conforms(to: $0) } } == true
    }

    private static func isHDR(_ space: CGColorSpace?) -> Bool {
        space.map { CGColorSpaceUsesITUR_2100TF($0) || CGColorSpaceUsesExtendedRange($0) } ?? false
    }

    /// `space` if an 8-bit RGB context can use it (not extended, not grey/CMYK).
    private static func sdrSpace(_ space: CGColorSpace) -> CGColorSpace? {
        space.model == .rgb && !isHDR(space) ? space : nil
    }

    /// `image` shrunk so its longest side is `longestSide`; nil if it's already that small.
    /// Our own decoders return full size; this brings them to the size ImageIO's would have.
    static func scaled(_ image: CGImage, longestSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longestSide > 0, longest > longestSide else { return nil }
        let scale = Double(longestSide) / Double(longest)
        return redrawn(image, width: max(1, Int((Double(image.width) * scale).rounded())),
                       height: max(1, Int((Double(image.height) * scale).rounded())),
                       in: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// `image` drawn into an RGB(A) bitmap of the given size and color space: 8-bit, or 16-bit half float.
    private static func redrawn(_ image: CGImage, width: Int, height: Int, in space: CGColorSpace,
                                bitsPerComponent: Int = 8) -> CGImage? {
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let float = bitsPerComponent == 16
            ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : 0
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: space,
            bitmapInfo: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue | float) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
