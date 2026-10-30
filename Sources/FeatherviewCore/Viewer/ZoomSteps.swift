import CoreGraphics

/// Where every new image starts unless Keep Zoom is on: fit, or one side filling the fit area.
public enum FitMode: String, Sendable, CaseIterable { case fit, width, height }

/// Where a picture is placed when it arrives: `keep` the relative position (also fit, where the clip
/// centres it), `top` for Zoom to Width, `leading` for Zoom to Height.
public enum ZoomStart: Equatable, Sendable { case keep, top, leading }

/// Zoom factors: 1 = one image pixel per screen pixel.
public enum ZoomSteps {
    public static let range = 0.05...16.0

    /// `factor` kept within `range`.
    public static func clamped(_ factor: Double) -> Double { min(max(factor, range.lowerBound), range.upperBound) }

    /// `factor` as a whole percentage, the way the viewer shows it.
    public static func percent(_ factor: Double) -> Int { Int((factor * 100).rounded()) }

    /// The factor fit mode shows an image at. Fit shrinks to the view and never enlarges.
    public static func fitFactor(image: CGSize, view: CGSize, displayScale: Double) -> Double {
        guard image.width > 0, image.height > 0 else { return 1 }
        return min(1, view.width * displayScale / image.width, view.height * displayScale / image.height)
    }

    /// The factor that makes one side of the image fill `view` (enlarging small images), within `range`.
    /// `.fit` is `fitFactor`.
    public static func fillFactor(image: CGSize, view: CGSize, displayScale: Double, mode: FitMode) -> Double {
        guard image.width > 0, image.height > 0, view.width > 0, view.height > 0 else { return 1 }
        let factor: Double
        switch mode {
        case .fit: return fitFactor(image: image, view: view, displayScale: displayScale)
        case .width: factor = view.width * displayScale / image.width
        case .height: factor = view.height * displayScale / image.height
        }
        return clamped(factor)
    }

    /// The clear area's top-leading corner in document coordinates (flipped, y down) for a picture
    /// arriving at `start`; nil for `.keep`. Unclamped: the clip view clamps and centres.
    /// The picture never mirrors; only the leading edge follows the reading direction.
    public static func startOrigin(_ start: ZoomStart, document: CGSize, clear: CGSize, rightToLeft: Bool) -> CGPoint? {
        switch start {
        case .keep: return nil
        case .top: return CGPoint(x: (document.width - clear.width) / 2, y: 0)
        case .leading: return CGPoint(x: rightToLeft ? document.width - clear.width : 0,
                                      y: (document.height - clear.height) / 2)
        }
    }

    /// From 2× on (each image pixel at least 2×2 screen pixels) the viewer shows sharp pixels instead of smoothing.
    /// `drawnWidth` is in points, so the display scale turns it into screen pixels.
    public static func showsPixels(drawnWidth: Double, imageWidth: Int, displayScale: Double) -> Bool {
        drawnWidth * displayScale >= Double(imageWidth) * 2
    }

    /// Whether the picture layer smooths: below 2×, or always when it holds the fit picture enlarged under the
    /// parts of a huge one (`byParts`), whose pixels are many times the file's and would show as blocks.
    public static func smoothsPicture(drawnWidth: Double, imageWidth: Int, displayScale: Double, byParts: Bool) -> Bool {
        byParts || !showsPixels(drawnWidth: drawnWidth, imageWidth: imageWidth, displayScale: displayScale)
    }

    /// One step (`by` 1.1 in, 1/1.1 out), kept within `range`.
    public static func step(_ factor: Double, by multiplier: Double) -> Double {
        clamped(factor * multiplier)
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
