import CoreGraphics
import CoreImage
import Foundation
import os

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

    /// HDR keeps values above 1.0: an extended linear working space.
    // shortcut: colour steps on HDR act on linear light, not the encoded values the SDR path uses; match them if anyone compares.
    static let hdrContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
    ])

    /// 8-bit sRGB, straight alpha, extent origin (0, 0). Throws `EncodeError.failed` for an
    /// empty or infinite extent.
    public static func cgImage(_ image: CIImage) throws -> CGImage { try cgImage(image, hdr: false) }

    /// With `hdr`, a 16-bit float image in extended linear Display P3 (what ImageIO writes as an HDR
    /// gain map), else as `cgImage(_:)`.
    public static func cgImage(_ image: CIImage, hdr: Bool) throws -> CGImage {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, extent.width.isFinite, extent.height.isFinite else {
            throw EncodeError.failed
        }
        let rect = extent.integral
        if hdr {
            guard let cg = hdrContext.createCGImage(image, from: rect, format: .RGBAh,
                                                    colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!)
            else { throw EncodeError.failed }
            return cg
        }
        let width = Int(rect.width), height = Int(rect.height), bytesPerRow = width * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Core Image always writes premultiplied (an `unpremultiplyingAlpha()` before the render is undone
        // after any filter). Each strip renders to 8 bits; one with half-transparent pixels renders again in
        // floats (Float, not Float16: Intel Macs lack it), un-premultiplied before rounding, so faint pixels keep their colour. Opaque strips stay one pass.
        let stripRows = max(1, min(height, (1 << 20) / width))
        var strip = [Float]()
        let size = bytesPerRow * height
        guard let base = outputBuffer(size: size) else { throw EncodeError.failed }
        let buffer = UnsafeMutableRawBufferPointer(start: base, count: size)
        do {
            let out = buffer.bindMemory(to: UInt8.self)
            for top in stride(from: 0, to: height, by: stripRows) {
                let rows = min(stripRows, height - top), base = top * bytesPerRow
                let bounds = CGRect(x: rect.minX, y: rect.maxY - CGFloat(top + rows), width: rect.width, height: CGFloat(rows))
                context.render(image, toBitmap: buffer.baseAddress! + base, rowBytes: bytesPerRow, bounds: bounds,
                               format: .RGBA8, colorSpace: space)
                let end = base + rows * bytesPerRow
                guard stride(from: base + 3, to: end, by: 4).contains(where: { out[$0] != 0 && out[$0] != 255 }) else { continue }
                if strip.isEmpty { strip = [Float](repeating: 0, count: width * stripRows * 4) }
                strip.withUnsafeMutableBufferPointer { f in
                    context.render(image, toBitmap: f.baseAddress!, rowBytes: width * 16, bounds: bounds,
                                   format: .RGBAf, colorSpace: space)
                    for i in stride(from: 0, to: end - base, by: 4) where out[base + i + 3] != 255 {
                        let alpha = min(1, max(0, Float(f[i + 3])))
                        let scale = alpha > 0 ? 255 / alpha : 0
                        for c in 0..<3 { out[base + i + c] = UInt8((min(255, max(0, Float(f[i + c]) * scale))).rounded()) }
                        out[base + i + 3] = UInt8((alpha * 255).rounded())
                    }
                }
            }
        }
        guard let provider = CGDataProvider(dataInfo: nil, data: base, size: size,
                                            releaseData: { _, data, size in PipelineRender.giveBack(UnsafeMutableRawPointer(mutating: data), size: size) })
        else { giveBack(base, size: size); throw EncodeError.failed }
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: bytesPerRow, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw EncodeError.failed }
        return cg
    }

    // Output buffers come straight from the kernel, not malloc: macOS 27's malloc keeps every freed block
    // this size counted against the app (~50–70 MB per output, ~2 GB over a batch, reclaimed only under
    // pressure). Fresh pages must be zeroed (~8 % slower), so released ones wait here for the next output
    // of the same size, at most one per core; `releaseBuffers()` unmaps them when a batch ends.
    private static let spare = OSAllocatedUnfairLock<[(base: UInt, size: Int)]>(initialState: [])

    private static func outputBuffer(size: Int) -> UnsafeMutableRawPointer? {
        let reused = spare.withLock { list -> UInt? in
            list.firstIndex { $0.size == size }.map { list.remove(at: $0).base }
        }
        if let reused { return UnsafeMutableRawPointer(bitPattern: reused) }
        let base = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        return base == MAP_FAILED ? nil : base
    }

    private static func giveBack(_ base: UnsafeMutableRawPointer, size: Int) {
        let address = UInt(bitPattern: base)
        let kept = spare.withLock { list in
            guard list.count < ProcessInfo.processInfo.activeProcessorCount else { return false }
            list.append((address, size))
            return true
        }
        if !kept { munmap(base, size) }
    }

    /// Unmaps the buffers kept for reuse.
    public static func releaseBuffers() {
        for buffer in spare.withLock({ list in defer { list = [] }; return list }) {
            munmap(UnsafeMutableRawPointer(bitPattern: buffer.base), buffer.size)
        }
    }
}
