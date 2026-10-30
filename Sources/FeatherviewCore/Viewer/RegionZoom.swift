import CoreGraphics

/// When a zoomed picture decodes only the part on screen, and which part.
/// All rects are in full-size pixels.
public enum RegionZoom {
    /// True when the zoom step's decode holds more than 4 × the largest screen's pixel area.
    public static func usesRegion(image: PixelSize, step: Int, screens: [PixelSize]) -> Bool {
        let screenArea = screens.map { $0.width * $0.height }.max() ?? 0
        let stepArea = ImageDecoder.stepSize(full: image.width, step: step)
            * ImageDecoder.stepSize(full: image.height, step: step)
        return stepArea > 4 * screenArea
    }

    /// `visible` grown by half its size on each side, snapped outward to the step's
    /// pixel grid and clamped to the picture.
    public static func region(visible: CGRect, image: PixelSize, step: Int) -> CGRect {
        let unit = 1 << min(max(step, 0), 3)
        func span(_ lo: CGFloat, _ hi: CGFloat, _ limit: Int) -> (Int, Int) {
            let half = (hi - lo) / 2
            let start = Int((lo - half).rounded(.down))
            let end = Int((hi + half).rounded(.up))
            let snappedStart = Int((Double(start) / Double(unit)).rounded(.down)) * unit
            let snappedEnd = Int((Double(end) / Double(unit)).rounded(.up)) * unit
            return (max(snappedStart, 0), min(snappedEnd, limit))
        }
        let (x0, x1) = span(visible.minX, visible.maxX, image.width)
        let (y0, y1) = span(visible.minY, visible.maxY, image.height)
        return CGRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }

    /// The decode size of `region` at `step`: each side divided by the step's factor, rounded up.
    public static func decodeSize(region: CGRect, step: Int) -> PixelSize {
        PixelSize(width: ImageDecoder.stepSize(full: Int(region.width), step: step),
                  height: ImageDecoder.stepSize(full: Int(region.height), step: step))
    }

    /// True when `visible` (clamped to the picture) comes within an eighth of its own
    /// width (height) of a side of `decoded` that isn't the picture's edge.
    public static func needsNewRegion(visible: CGRect, decoded: CGRect, image: PixelSize) -> Bool {
        let v = visible.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if v.isNull { return false }
        let mx = v.width / 8, my = v.height / 8
        if decoded.minX > 0, v.minX - decoded.minX < mx { return true }
        if decoded.maxX < CGFloat(image.width), decoded.maxX - v.maxX < mx { return true }
        if decoded.minY > 0, v.minY - decoded.minY < my { return true }
        if decoded.maxY < CGFloat(image.height), decoded.maxY - v.maxY < my { return true }
        return false
    }
}
