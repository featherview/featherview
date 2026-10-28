import Accelerate
import CoreGraphics
import Foundation
import os

/// The info panel's histogram: 256 bins per channel, computed from the picture already decoded for the screen.
public struct Histogram: Equatable, Sendable {
    /// 256 bins each, normalised so the tallest bin of luminance is 1.
    public var luminance: [Float]
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    /// Fractions 0...1 of the non-transparent pixels whose luminance is at black / at the brightest level
    /// (255 for SDR, the headroom for HDR).
    public var shadowsClipped: Double
    public var highlightsClipped: Double
    /// nil for SDR; > 1 for HDR, where the bins span linear 0...headroom.
    public var headroom: Double?

    /// Above this fraction a clip mark is filled.
    public var clipThreshold: Double { 0.001 }

    /// Rec. 709 luminance weights for R, G, B.
    private static let weights: (Float, Float, Float) = (0.2126, 0.7152, 0.0722)

    /// Counts `image` off the caller's actor, in a child of the calling task: nil once that task is cancelled,
    /// which also stops the count.
    /// `fitting`: scale `image` down to fit these screens first (a zoom decode, which can be full size).
    public static func counted(_ image: CGImage, headroom: Double?, fitting screens: [PixelSize]? = nil) async -> Histogram? {
        let stopped = OSAllocatedUnfairLock(initialState: false)
        let result: Histogram? = await withTaskCancellationHandler {
            guard !Task.isCancelled, let image = screens.map({ fitted(image, screens: $0) }) ?? image else { return nil }
            return compute(image, headroom: headroom, stop: { stopped.withLock { $0 } })
        } onCancel: {
            stopped.withLock { $0 = true }
        }
        return Task.isCancelled ? nil : result
    }

    /// `headroom` is the file's; a picture decoded SDR (no extended range, no PQ/HLG, as before macOS 15) is counted
    /// as SDR whatever it is. `stop` is polled from every worker thread; a stopped count is incomplete.
    public static func compute(_ image: CGImage, headroom: Double?, stop: @Sendable () -> Bool = { false }) -> Histogram {
        let headroom = ImageDecoder.isHDR(image.colorSpace) ? headroom : nil
        let counts = if let headroom, headroom > 1 { hdrCounts(image, headroom: headroom, stop: stop) } else { sdrCounts(image, stop: stop) }
        let pixels = Double(max(1, counts.total))
        let tallest = Float(counts.luminance.max() ?? 0)
        let scale: ([UInt]) -> [Float] = { bins in bins.map { tallest > 0 ? Float($0) / tallest : 0 } }
        return Histogram(
            luminance: scale(counts.luminance), red: scale(counts.red), green: scale(counts.green), blue: scale(counts.blue),
            shadowsClipped: Double(counts.shadows) / pixels, highlightsClipped: Double(counts.highlights) / pixels,
            headroom: headroom.flatMap { $0 > 1 ? $0 : nil })
    }

    /// `image` itself, or for a packed pixel format vImage can't convert (the viewer's 10-bit decodes of a JPEG with
    /// a gain map) the same picture drawn the way `fitted` draws, at most 2560 × 1600 pixels: drawing all of a 12 MP
    /// decode takes ~13 ms, twice the budget, and 256 bins don't need it.
    private static func unpacked(_ image: CGImage, hdr: Bool) -> CGImage? {
        guard image.pixelFormatInfo != .packed else { return image }
        let scale = min(1, (Double(2560 * 1600) / Double(max(1, image.width * image.height))).squareRoot())
        let width = max(1, Int((Double(image.width) * scale).rounded())), height = max(1, Int((Double(image.height) * scale).rounded()))
        let space = hdr ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            : image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | (hdr ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : 0)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: hdr ? 16 : 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// `image` scaled down to the size that fits `screens` when it is larger, so a count copies no more pixels than a
    /// fit decode has; `image` itself when it already fits. HDR is drawn in extended linear sRGB, which the count
    /// converts to anyway. nil if no context can be made.
    public static func fitted(_ image: CGImage, screens: [PixelSize]) -> CGImage? {
        let longest = max(image.width, image.height)
        let target = ImageDecoder.fitNeededSize(image: PixelSize(width: image.width, height: image.height), screens: screens)
        guard target < longest else { return image }
        let width = max(1, (image.width * target + longest / 2) / longest)
        let height = max(1, (image.height * target + longest / 2) / longest)
        let hdr = ImageDecoder.isHDR(image.colorSpace)
        let space = hdr ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            : image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | (hdr ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : 0)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: hdr ? 16 : 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Bins, the pixels at black and at the brightest level, and all pixels counted (transparent ones are left out).
    private typealias Counts = (luminance: [UInt], red: [UInt], green: [UInt], blue: [UInt],
                                shadows: UInt, highlights: UInt, total: Int)

    private static let empty: Counts = ([UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256),
                                        [UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256), 0, 0, 0)

    /// RGBA8 levels in the picture's own RGB space (sRGB for other spaces), straight alpha, every pixel;
    /// luminance from the encoded values as photo editors show it.
    private static func sdrCounts(_ image: CGImage, stop: @Sendable () -> Bool) -> Counts {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let image = unpacked(image, hdr: false), image.width > 0, image.height > 0,
              let format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
              let source = try? vImage_Buffer(cgImage: image, format: format) else { return empty }
        defer { source.free() }
        let width = Int(source.width), height = Int(source.height)
        // vImage's histograms run on one core (~2.5 ms each for 2560 × 1600): count row strips in parallel.
        let strips = min(height, 8), stripRows = (height + strips - 1) / strips
        var parts = [UInt](repeating: 0, count: strips * 5 * 256)  // per strip: R, G, B, A, luminance
        var plane = [UInt8](repeating: 0, count: width * stripRows * strips)
        parts.withUnsafeMutableBufferPointer { partsBuffer in
            plane.withUnsafeMutableBytes { planeBuffer in
                // Each strip reads and writes only its own rows and bins.
                nonisolated(unsafe) let source = source, parts = partsBuffer, plane = planeBuffer
                DispatchQueue.concurrentPerform(iterations: strips) { strip in
                    let first = strip * stripRows, rows = min(stripRows, height - first)
                    guard rows > 0, !stop() else { return }
                    var part = vImage_Buffer(data: source.data + first * source.rowBytes, height: vImagePixelCount(rows),
                                             width: source.width, rowBytes: source.rowBytes)
                    let bins = parts.baseAddress! + strip * 5 * 256
                    var pointers: [UnsafeMutablePointer<vImagePixelCount>?] = (0..<4).map { bins + $0 * 256 }
                    _ = vImageHistogramCalculation_ARGB8888(&part, &pointers, vImage_Flags(kvImageNoFlags))
                    // Fully transparent pixels keep whatever colour they had: make them (0, 0, 0, 0), recount, and
                    // take them out of every bin 0 below.
                    if bins[768] > 0 {
                        for row in 0..<rows {
                            let pixels = (part.data + row * part.rowBytes).assumingMemoryBound(to: UInt32.self)
                            for x in 0..<width where pixels[x] & 0xFF00_0000 == 0 { pixels[x] = 0 }  // A is the high byte
                        }
                        _ = vImageHistogramCalculation_ARGB8888(&part, &pointers, vImage_Flags(kvImageNoFlags))
                    }
                    var destination = vImage_Buffer(data: plane.baseAddress! + first * width, height: vImagePixelCount(rows),
                                                    width: vImagePixelCount(width), rowBytes: width)
                    let divisor: Int32 = 0x8000
                    let matrix: [Int16] = [6966, 23436, 2366, 0]  // the weights × 32768, summing to 32768 so white stays 255
                    _ = vImageMatrixMultiply_ARGB8888ToPlanar8(&part, &destination, matrix, divisor, nil, divisor / 2,
                                                               vImage_Flags(kvImageNoFlags))
                    _ = vImageHistogramCalculation_Planar8(&destination, bins + 1024, vImage_Flags(kvImageNoFlags))
                }
            }
        }
        var sums = [UInt](repeating: 0, count: 5 * 256)
        for strip in 0..<strips { for i in 0..<(5 * 256) { sums[i] += parts[strip * 5 * 256 + i] } }
        let transparent = sums[768]
        for bin in [0, 256, 512, 1024] { sums[bin] -= transparent }
        let luminance = Array(sums[1024..<1280])
        return (luminance, Array(sums[0..<256]), Array(sums[256..<512]), Array(sums[512..<768]),
                luminance[0], luminance[255], width * height - Int(transparent))
    }

    /// Extended linear sRGB floats, straight alpha, every pixel, binned over 0...headroom; values outside land in
    /// the end bins. Clipping is counted from the values themselves: luminance <= 0 and >= headroom.
    private static func hdrCounts(_ image: CGImage, headroom: Double, stop: @Sendable () -> Bool) -> Counts {
        guard let image = unpacked(image, hdr: true), image.width > 0, image.height > 0,
              let format = vImage_CGImageFormat(
                  bitsPerComponent: 32, bitsPerPixel: 128, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.floatComponents.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue)),
              let source = try? vImage_Buffer(cgImage: image, format: format) else { return empty }
        defer { source.free() }
        let width = Int(source.width), height = Int(source.height)
        // Float rounding (the weights' sum, the conversion) leaves a value at the headroom a few ulps low: it still clips.
        let scale = Float(255 / headroom), top = Float(headroom) * (1 - 1e-6)
        let strips = min(height, 32), stripRows = (height + strips - 1) / strips
        let stride = 4 * 256 + 3  // per strip: R, G, B, luminance bins, then shadows, highlights, total
        var parts = [UInt](repeating: 0, count: strips * stride)
        parts.withUnsafeMutableBufferPointer { partsBuffer in
            // Each strip reads its own rows and writes its own counts.
            nonisolated(unsafe) let source = source, parts = partsBuffer
            DispatchQueue.concurrentPerform(iterations: strips) { strip in
                let bins = parts.baseAddress! + strip * stride
                let (wr, wg, wb) = weights
                // max(0, NaN) is 0. Floor plus 2^23 leaves the bin in the low bits: no checked Int conversion per channel.
                func bin(_ value: Float) -> Int {
                    value >= top ? 255 : Int((min(255, max(0, value * scale)).rounded(.down) + 0x1p23).bitPattern & 0xFF)
                }
                for row in (strip * stripRows)..<min(height, (strip + 1) * stripRows) {
                    if row % 64 == 0, stop() { break }
                    let pixels = (source.data + row * source.rowBytes).assumingMemoryBound(to: Float.self)
                    for i in Swift.stride(from: 0, to: width * 4, by: 4) where pixels[i + 3] > 0 {
                        let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                        let y = wr * r + wg * g + wb * b
                        bins[bin(r)] += 1
                        bins[256 + bin(g)] += 1
                        bins[512 + bin(b)] += 1
                        bins[768 + bin(y)] += 1
                        if y <= 0 { bins[1024] += 1 } else if y >= top { bins[1025] += 1 }
                        bins[1026] += 1
                    }
                }
            }
        }
        var sums = [UInt](repeating: 0, count: stride)
        for strip in 0..<strips { for i in 0..<stride { sums[i] += parts[strip * stride + i] } }
        return (Array(sums[768..<1024]), Array(sums[0..<256]), Array(sums[256..<512]), Array(sums[512..<768]),
                sums[1024], sums[1025], Int(sums[1026]))
    }
}

public enum HistogramText {
    /// "Highlights: 2.4 % clipped" / "Shadows: 0.0 % clipped".
    public static func clipped(_ fraction: Double, highlights: Bool) -> String {
        let percent = (fraction * 100).formatted(.number.precision(.fractionLength(1)))
        return highlights
            ? String(localized: "Highlights: \(percent) % clipped", comment: "Info panel histogram: share of pixels at the brightest level")
            : String(localized: "Shadows: \(percent) % clipped", comment: "Info panel histogram: share of pixels at the darkest level")
    }
}
