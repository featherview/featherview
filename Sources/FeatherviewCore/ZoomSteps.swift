import CoreGraphics

/// Zoom factors: 1 = one image pixel per screen pixel.
public enum ZoomSteps {
    public static let range = 0.05...16.0

    /// The factor fit mode shows an image at. Fit shrinks to the view and never enlarges.
    public static func fitFactor(image: CGSize, view: CGSize, displayScale: Double) -> Double {
        guard image.width > 0, image.height > 0 else { return 1 }
        return min(1, view.width * displayScale / image.width, view.height * displayScale / image.height)
    }

    /// From 2× on (each image pixel at least 2×2 screen pixels) the viewer shows sharp pixels instead of smoothing.
    /// `drawnWidth` is in points, so the display scale turns it into screen pixels.
    public static func showsPixels(drawnWidth: Double, imageWidth: Int, displayScale: Double) -> Bool {
        drawnWidth * displayScale >= Double(imageWidth) * 2
    }

    /// One step (`by` 1.1 in, 1/1.1 out), kept within `range`.
    public static func step(_ factor: Double, by multiplier: Double) -> Double {
        min(max(factor * multiplier, range.lowerBound), range.upperBound)
    }
}
