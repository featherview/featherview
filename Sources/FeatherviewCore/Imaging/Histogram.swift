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
    /// Fractions 0...1 of the pixels whose luminance is in the darkest / brightest bin.
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
        let pixels = Double(max(1, image.width * image.height))
        let tallest = Float(counts.luminance.max() ?? 0)
        let scale: ([UInt]) -> [Float] = { bins in bins.map { tallest > 0 ? Float($0) / tallest : 0 } }
        return Histogram(
            luminance: scale(counts.luminance), red: scale(counts.red), green: scale(counts.green), blue: scale(counts.blue),
            shadowsClipped: Double(counts.luminance[0]) / pixels, highlightsClipped: Double(counts.luminance[255]) / pixels,
            headroom: headroom.flatMap { $0 > 1 ? $0 : nil })
    }

    private typealias Counts = (luminance: [UInt], red: [UInt], green: [UInt], blue: [UInt])

    private static let empty: Counts = ([UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256),
                                        [UInt](repeating: 0, count: 256), [UInt](repeating: 0, count: 256))

    /// sRGB RGBA8 levels, luminance from the encoded values as photo editors show it.
    private static func sdrCounts(_ image: CGImage) -> Counts {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return empty }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)

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
        return (luminance, Array(channels[0..<256]), Array(channels[256..<512]), Array(channels[512..<768]))
    }

    /// Extended linear sRGB floats binned over 0...headroom; values outside land in the end bins.
    private static func hdrCounts(_ image: CGImage, headroom: Double) -> Counts {
        let width = image.width, height = image.height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard width > 0, height > 0,
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                          bytesPerRow: width * 16, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                                              | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return empty }
        var counts = empty
        let scale = Float(255 / headroom)
        func bin(_ value: Float) -> Int { value.isNaN ? 0 : Int(min(255, max(0, value * scale))) }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
            counts.red[bin(r)] += 1
            counts.green[bin(g)] += 1
            counts.blue[bin(b)] += 1
            counts.luminance[bin(weights.0 * r + weights.1 * g + weights.2 * b)] += 1
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
