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
        // Core Image always writes premultiplied (an `unpremultiplyingAlpha()` before the render is undone
        // after any filter), so it renders float strips that are un-premultiplied here before rounding to
        // 8 bits: faint pixels keep their colour. Strips bound the float buffer for large images.
        let stripRows = max(1, min(height, (1 << 20) / width))
        var strip = [Float](repeating: 0, count: width * stripRows * 4)
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buffer in
            let out = buffer.bindMemory(to: UInt8.self)
            for top in stride(from: 0, to: height, by: stripRows) {
                let rows = min(stripRows, height - top)
                let bounds = CGRect(x: rect.minX, y: rect.maxY - CGFloat(top + rows), width: rect.width, height: CGFloat(rows))
                strip.withUnsafeMutableBytes { f in
                    context.render(image, toBitmap: f.baseAddress!, rowBytes: width * 16, bounds: bounds,
                                   format: .RGBAf, colorSpace: space)
                }
                let base = top * bytesPerRow
                for i in stride(from: 0, to: rows * width * 4, by: 4) {
                    let alpha = min(1, max(0, strip[i + 3]))
                    out[base + i + 3] = UInt8((alpha * 255).rounded())
                    guard alpha > 0 else { continue }
                    for c in 0..<3 { out[base + i + c] = UInt8((min(1, max(0, strip[i + c] / alpha)) * 255).rounded()) }
                }
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
