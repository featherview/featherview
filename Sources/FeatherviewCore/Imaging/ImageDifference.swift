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

    /// At the first's pixel size, RGBA8 in `colorSpace` (sRGB when nil). The second is scaled to fit
    /// the first's box and centred; outside it the first shows through. Both are flattened over black.
    /// Synchronous: run it off the main thread.
    public static func make(_ first: CGImage, _ second: CGImage, colorSpace: CGColorSpace?) throws -> CGImage {
        let box = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        let black = CIImage(color: .black).cropped(to: box)
        // CompareSync.scale's formula (1 when either size is empty).
        let w2 = CGFloat(second.width), h2 = CGFloat(second.height)
        let s = w2 > 0 && h2 > 0 && box.width > 0 && box.height > 0 ? min(box.width / w2, box.height / h2) : 1
        let placed = CIImage(cgImage: second)
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: (box.width - w2 * s) / 2, y: (box.height - h2 * s) / 2))
        let filter = CIFilter.differenceBlendMode()
        filter.inputImage = CIImage(cgImage: first).composited(over: black)
        filter.backgroundImage = placed.composited(over: black)
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let image = Signposts.poster.withIntervalSignpost("Difference") {
            filter.outputImage.flatMap { context.createCGImage($0, from: box, format: .RGBA8, colorSpace: space) }
        }
        guard let image else { throw Failure.render }
        return image
    }
}
