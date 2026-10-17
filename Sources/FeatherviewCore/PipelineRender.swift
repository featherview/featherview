import CoreGraphics
import CoreImage
import Foundation

/// The one render at the end of the batch pipeline: every step builds a `CIImage` recipe, and this
/// turns it into pixels once, in tiles, through one shared context.
public enum PipelineRender {
    /// Colour arithmetic acts on the values the user sees (sRGB, not Core Image's linear default).
    /// Thread-safe and expensive to create: shared by every worker.
    public static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
    ])

    /// 8-bit sRGB, straight alpha, extent origin (0, 0). Throws `EncodeError.failed` for an
    /// empty or infinite extent.
    public static func cgImage(_ image: CIImage) throws -> CGImage {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, extent.width.isFinite, extent.height.isFinite else {
            throw EncodeError.failed
        }
        let rect = extent.integral
        let width = Int(rect.width), height = Int(rect.height), bytesPerRow = width * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Core Image's values are premultiplied; un-premultiplied first, the bytes it writes are straight.
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buffer in
            context.render(image.unpremultiplyingAlpha(), toBitmap: buffer.baseAddress!, rowBytes: bytesPerRow,
                           bounds: rect, format: .RGBA8, colorSpace: space)
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: bytesPerRow, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw EncodeError.failed }
        return cg
    }
}
