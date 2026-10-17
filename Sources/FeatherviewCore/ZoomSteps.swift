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

    /// The file's pixel size `decoded` stands for: `full` when it has the same proportions, else `decoded`
    /// (a size read before a rotation would draw the rotated image stretched).
    public static func pixelSize(decoded: CGSize, full: CGSize?) -> CGSize {
        guard let full else { return decoded }
        // A decode step rounds each side by up to a pixel, so the cross products differ by at most this much.
        let sameShape = abs(full.width * decoded.height - full.height * decoded.width) <= full.width + full.height
        return sameShape ? full : decoded
    }

    /// Points to draw `decoded` at. Fit: shrink to `view`, never enlarge (as today, from `decoded`).
    /// Factor: from `full` (the file's displayed pixel size) when known, so a smaller decode shown
    /// while the full one loads already has its final size; from `decoded` when `full` is nil.
    public static func drawSize(decoded: CGSize, full: CGSize?, factor: Double?, view: CGSize,
                                displayScale: Double) -> CGSize {
        guard let factor else {
            let points = CGSize(width: decoded.width / displayScale, height: decoded.height / displayScale)
            let scale = min(1, view.width / max(points.width, 1), view.height / max(points.height, 1))
            return CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
        }
        let pixels = pixelSize(decoded: decoded, full: full)
        return CGSize(width: pixels.width / displayScale * factor, height: pixels.height / displayScale * factor)
    }
}
