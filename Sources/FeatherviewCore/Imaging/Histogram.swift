import Accelerate
import CoreGraphics
import Foundation

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

    public static func compute(_ image: CGImage, headroom: Double?) -> Histogram {
        let counts = if let headroom, headroom > 1 { hdrCounts(image, headroom: headroom) } else { sdrCounts(image) }
        let pixels = Double(max(1, counts.total))
        let tallest = Float(counts.luminance.max() ?? 0)
        let scale: ([UInt]) -> [Float] = { bins in bins.map { tallest > 0 ? Float($0) / tallest : 0 } }
        return Histogram(
            luminance: scale(counts.luminance), red: scale(counts.red), green: scale(counts.green), blue: scale(counts.blue),
            shadowsClipped: Double(counts.shadows) / pixels, highlightsClipped: Double(counts.highlights) / pixels,
            headroom: headroom.flatMap { $0 > 1 ? $0 : nil })
    }

    /// Bins, the pixels at black and at the brightest level, and all pixels counted (transparent ones are left out).
    private typealias Counts = (luminance: [UInt], red: [UInt], green: [UInt], blue: [UInt],
                                shadows: UInt, highlights: UInt, total: Int)

    private static let empty: Counts = ([UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256),
                                        [UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256), 0, 0, 0)

    /// Pictures are sampled down to about this many pixels: a 5K fit decode stays within a few ms.
    private static let samplePixels = 1 << 18

    private static func sampleSize(_ image: CGImage) -> (width: Int, height: Int) {
        let factor = min(1, (Double(samplePixels) / Double(max(1, image.width * image.height))).squareRoot())
        return (max(1, Int(Double(image.width) * factor)), max(1, Int(Double(image.height) * factor)))
    }

    /// sRGB RGBA8 levels, luminance from the encoded values as photo editors show it.
    private static func sdrCounts(_ image: CGImage) -> Counts {
        let (width, height) = sampleSize(image)
        guard image.width > 0, image.height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return empty }
        context.interpolationQuality = .none  // samples, so clipped values stay clipped
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
        _ = vImageUnpremultiplyData_RGBA8888(&source, &source, vImage_Flags(kvImageNoFlags))

        var channels = [UInt](repeating: 0, count: 4 * 256)
        channels.withUnsafeMutableBufferPointer { bins in
            var pointers: [UnsafeMutablePointer<vImagePixelCount>?] = (0..<4).map { bins.baseAddress! + $0 * 256 }
            _ = vImageHistogramCalculation_ARGB8888(&source, &pointers, vImage_Flags(kvImageNoFlags))
        }

        var plane = [UInt8](repeating: 0, count: width * height)
        var luminance = [UInt](repeating: 0, count: 256)
        plane.withUnsafeMutableBytes { planeBytes in
            var destination = vImage_Buffer(data: planeBytes.baseAddress, height: vImagePixelCount(height),
                                            width: vImagePixelCount(width), rowBytes: width)
            let divisor: Int32 = 0x8000
            let matrix: [Int16] = [6966, 23436, 2366, 0]  // the weights × 32768, summing to 32768 so white stays 255
            _ = vImageMatrixMultiply_ARGB8888ToPlanar8(&source, &destination, matrix, divisor, nil, divisor / 2,
                                                       vImage_Flags(kvImageNoFlags))
            _ = vImageHistogramCalculation_Planar8(&destination, &luminance, vImage_Flags(kvImageNoFlags))
        }
        // Fully transparent pixels are (0, 0, 0, 0) here: take them out of every bin 0 and the total.
        let transparent = channels[768]
        for bin in [0, 256, 512] { channels[bin] -= transparent }
        luminance[0] -= transparent
        return (luminance, Array(channels[0..<256]), Array(channels[256..<512]), Array(channels[512..<768]),
                luminance[0], luminance[255], width * height - Int(transparent))
    }

    /// Extended linear sRGB floats binned over 0...headroom; values outside land in the end bins. Clipping is
    /// counted from the values themselves: luminance <= 0 and >= headroom.
    private static func hdrCounts(_ image: CGImage, headroom: Double) -> Counts {
        let (width, height) = sampleSize(image)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard image.width > 0, image.height > 0,
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                          bytesPerRow: width * 16, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.interpolationQuality = .none  // samples, so clipped values stay clipped
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return empty }
        var counts = empty
        let scale = Float(255 / headroom), top = Float(headroom)
        func bin(_ value: Float) -> Int { value.isNaN ? 0 : Int(min(255, max(0, value * scale))) }
        for row in 0..<height {
            if row % 64 == 0, Task.isCancelled { break }
            for i in stride(from: row * width * 4, to: (row + 1) * width * 4, by: 4) {
                let a = pixels[i + 3]
                guard a > 0 else { continue }
                let r = pixels[i] / a, g = pixels[i + 1] / a, b = pixels[i + 2] / a
                let y = weights.0 * r + weights.1 * g + weights.2 * b
                counts.red[bin(r)] += 1
                counts.green[bin(g)] += 1
                counts.blue[bin(b)] += 1
                counts.luminance[bin(y)] += 1
                if y <= 0 { counts.shadows += 1 } else if y >= top { counts.highlights += 1 }
                counts.total += 1
            }
        }
        return counts
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
