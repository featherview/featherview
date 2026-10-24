import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// |first − second| per channel, for compare's difference view.
public enum ImageDifference {
    public enum Failure: Error { case render }

    /// Differences act on the values the user sees (sRGB, not Core Image's linear default).
    /// Created on first use, never at launch; thread-safe.
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
    ])

    /// Sets up the context and its GPU pipeline with a 1 × 1 difference, so the first D doesn't pay
    /// for that (~50–80 ms on first use). Synchronous: run it off the main thread.
    public static func prepare(colorSpace: CGColorSpace?) {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage() else { return }
        _ = render(pixel, pixel, colorSpace: space)
    }

    /// At the first's pixel size, RGBA8 in `colorSpace` (sRGB when nil). The second is scaled to fit
    /// the first's box and centred; outside it the first shows through. Both are flattened over black.
    /// Synchronous: run it off the main thread.
    public static func make(_ first: CGImage, _ second: CGImage, colorSpace: CGColorSpace?) throws -> CGImage {
        let image = Signposts.poster.withIntervalSignpost("Difference") { render(first, second, colorSpace: colorSpace) }
        guard let image else { throw Failure.render }
        return image
    }

    /// `make` without the signpost, so the warm-up doesn't show as a Difference.
    private static func render(_ first: CGImage, _ second: CGImage, colorSpace: CGColorSpace?) -> CGImage? {
        let box = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        let black = CIImage(color: .black).cropped(to: box)
        let w2 = CGFloat(second.width), h2 = CGFloat(second.height)
        let s = CompareSync.scale(first: box.size, second: CGSize(width: w2, height: h2))
        let placed = CIImage(cgImage: second)
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: (box.width - w2 * s) / 2, y: (box.height - h2 * s) / 2))
        let filter = CIFilter.differenceBlendMode()
        filter.inputImage = CIImage(cgImage: first).composited(over: black)
        filter.backgroundImage = placed.composited(over: black)
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return filter.outputImage.flatMap { context.createCGImage($0, from: box, format: .RGBA8, colorSpace: space) }
    }
}
