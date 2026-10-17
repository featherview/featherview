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
        // Core Image always writes RGBA8 premultiplied (an `unpremultiplyingAlpha()` before the render is
        // undone after any filter), so the bytes are un-premultiplied here.
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: bytesPerRow,
                           bounds: rect, format: .RGBA8, colorSpace: space)
            let p = buffer.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: p.count, by: 4) {
                let alpha = Int(p[i + 3])
                guard alpha > 0, alpha < 255 else { continue }
                for c in 0..<3 { p[i + c] = UInt8(min(255, (Int(p[i + c]) * 255 + alpha / 2) / alpha)) }
            }
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
