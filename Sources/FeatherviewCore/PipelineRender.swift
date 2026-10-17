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
        // after any filter). Each strip renders to 8 bits; one with half-transparent pixels renders again in half
        // floats, un-premultiplied before rounding, so faint pixels keep their colour. Opaque strips stay one pass.
        let stripRows = max(1, min(height, (1 << 20) / width))
        var strip = [Float16]()
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buffer in
            let out = buffer.bindMemory(to: UInt8.self)
            for top in stride(from: 0, to: height, by: stripRows) {
                let rows = min(stripRows, height - top), base = top * bytesPerRow
                let bounds = CGRect(x: rect.minX, y: rect.maxY - CGFloat(top + rows), width: rect.width, height: CGFloat(rows))
                context.render(image, toBitmap: buffer.baseAddress! + base, rowBytes: bytesPerRow, bounds: bounds,
                               format: .RGBA8, colorSpace: space)
                let end = base + rows * bytesPerRow
                guard stride(from: base + 3, to: end, by: 4).contains(where: { out[$0] != 0 && out[$0] != 255 }) else { continue }
                if strip.isEmpty { strip = [Float16](repeating: 0, count: width * stripRows * 4) }
                strip.withUnsafeMutableBufferPointer { f in
                    context.render(image, toBitmap: f.baseAddress!, rowBytes: width * 8, bounds: bounds,
                                   format: .RGBAh, colorSpace: space)
                    for i in stride(from: 0, to: end - base, by: 4) where out[base + i + 3] != 255 {
                        let alpha = min(1, max(0, Float(f[i + 3])))
                        let scale = alpha > 0 ? 255 / alpha : 0
                        for c in 0..<3 { out[base + i + c] = UInt8((min(255, max(0, Float(f[i + c]) * scale))).rounded()) }
                        out[base + i + 3] = UInt8((alpha * 255).rounded())
                    }
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
