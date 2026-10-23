import CoreGraphics
import CoreImage
import Foundation

/// Shown as "… leaves no image".
public enum CanvasError: Error, Equatable { case nothingLeft }

public enum AutoCropStep {
    /// Removes uniform borders: rows/columns at each edge whose every pixel is within 8/255 per
    /// channel of that edge's corner colour. A uniform image is left whole.
    public static func apply(_ image: CIImage) -> CIImage {
        let image = atOrigin(image)
        let width = Int(image.extent.width.rounded()), height = Int(image.extent.height.rounded())
        guard width > 0, height > 0 else { return image }
        // Full-size strips, scanned inward from each edge, stop at the first row or column that isn't border:
        // exact, and on a photo without borders only four thin strips are rendered.
        func strip(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> RGBAImage? {  // y from the top
            try? RGBAImage(PipelineRender.cgImage(image.cropped(to: CGRect(x: x, y: height - y - h, width: w, height: h))))
        }
        guard let topLeft = strip(0, 0, 1, 1)?[0, 0], let bottomRight = strip(width - 1, height - 1, 1, 1)?[0, 0]
        else { return image }
        func near(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            abs(Int(a.r) - Int(b.r)) <= 8 && abs(Int(a.g) - Int(b.g)) <= 8
                && abs(Int(a.b) - Int(b.b)) <= 8 && abs(Int(a.a) - Int(b.a)) <= 8
        }
        let chunk = 64
        /// How many lines from one edge are border. `render(start, count)` gives `count` lines starting
        /// `start` lines in from that edge, as rows (`rows`) or columns, ordered from the edge inward.
        func borderLines(_ total: Int, rows: Bool, _ colour: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
                         _ render: (Int, Int) -> RGBAImage?) -> Int? {
            var done = 0
            while done < total {
                let n = min(chunk, total - done)
                guard let s = render(done, n) else { return nil }
                for i in 0..<n {
                    let border = rows ? (0..<s.width).allSatisfy { near(s[$0, i], colour) }
                                      : (0..<s.height).allSatisfy { near(s[i, $0], colour) }
                    if !border { return done + i }
                }
                done += n
            }
            return total
        }
        // Each render is ordered from its edge inward: strips from the far edges are flipped by index.
        func flippedRows(_ s: RGBAImage?) -> RGBAImage? { s.map { flip($0, rows: true) } }
        func flippedColumns(_ s: RGBAImage?) -> RGBAImage? { s.map { flip($0, rows: false) } }
        guard let top = borderLines(height, rows: true, topLeft, { strip(0, $0, width, $1) }) else { return image }
        if top == height { return image }  // uniform
        guard let bottom = borderLines(height - top, rows: true, bottomRight,
                                       { flippedRows(strip(0, height - $0 - $1, width, $1)) }) else { return image }
        let y0 = top, y1 = height - bottom
        guard y1 > y0 else { return image }
        guard let left = borderLines(width, rows: false, topLeft, { strip($0, y0, $1, y1 - y0) }) else { return image }
        guard let right = borderLines(width - left, rows: false, bottomRight,
                                      { flippedColumns(strip(width - $0 - $1, y0, $1, y1 - y0)) }) else { return image }
        let x0 = left, x1 = width - right
        guard x1 > x0 else { return image }
        // Core Image's origin is the bottom-left corner.
        return atOrigin(image.cropped(to: CGRect(x: x0, y: height - y1, width: x1 - x0, height: y1 - y0)))
    }

    private static func flip(_ image: RGBAImage, rows: Bool) -> RGBAImage {
        var out = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                out[x, y] = rows ? image[x, image.height - 1 - y] : image[image.width - 1 - x, y]
            }
        }
        return out
    }
}

public enum CanvasStep {
    /// Runs auto-crop first when `s.autoCropBorders`.
    public static func apply(_ image: CIImage, _ s: CanvasSettings, scale: Double) throws -> CIImage {
        guard s.isOn else { return image }
        let image = s.autoCropBorders ? AutoCropStep.apply(image) : atOrigin(image)
        let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
        func scaled(_ v: Int) -> Int { clampedPixels(Double(v) * scale) }
        switch s.method {
        case .perSide:
            let left = scaled(s.left), right = scaled(s.right), top = scaled(s.top), bottom = scaled(s.bottom)
            return try place(image, width: w + left + right, height: h + top + bottom, left: left, top: top, colour: s.colour)
        case .totalSize:
            let width = s.width > 0 ? scaled(s.width) : w, height = s.height > 0 ? scaled(s.height) : h
            return try place(image, width: width, height: height, anchor: s.anchor, colour: s.colour)
        case .aspectRatio:
            guard s.ratioWidth > 0, s.ratioHeight > 0 else { return image }
            let ratio = s.ratioWidth / s.ratioHeight
            let width = max(w, clampedPixels(Double(h) * ratio)), height = max(h, clampedPixels(Double(w) / ratio))
            // Only one side grows: the other already fits the ratio.
            return Double(w) / Double(h) < ratio
                ? try place(image, width: width, height: h, anchor: s.anchor, colour: s.colour)
                : try place(image, width: w, height: height, anchor: s.anchor, colour: s.colour)
        }
    }
}

public enum BorderStep {
    public static func apply(_ image: CIImage, _ s: BorderSettings, scale: Double) -> CIImage {
        guard s.isOn else { return image }
        var image = atOrigin(image)
        for (width, colour) in [(s.innerWidth, s.innerColour), (s.outerWidth, s.outerColour)] {
            let b = clampedPixels(Double(width) * scale)
            guard b > 0 else { continue }
            let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
            // Growing a picture always leaves pixels: `place` can't throw here.
            image = (try? place(image, width: w + 2 * b, height: h + 2 * b, left: b, top: b, colour: colour)) ?? image
        }
        return image
    }
}

/// A typed value in pixels, clamped to ±2^30: sums of a few never overflow, no picture comes near 2^30
/// pixels a side, and the live preview sizes the output after every keystroke.
func clampedPixels(_ v: Double) -> Int { Int(min(max(v, -0x1p30), 0x1p30).rounded()) }

private func atOrigin(_ image: CIImage) -> CIImage {
    image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
}

private func place(_ image: CIImage, width: Int, height: Int, anchor: ImageAnchor, colour: RGBAColor) throws -> CIImage {
    let fx: Double, fy: Double  // from the left and from the top
    switch anchor {
    case .topLeft: (fx, fy) = (0, 0)
    case .top: (fx, fy) = (0.5, 0)
    case .topRight: (fx, fy) = (1, 0)
    case .left: (fx, fy) = (0, 0.5)
    case .center: (fx, fy) = (0.5, 0.5)
    case .right: (fx, fy) = (1, 0.5)
    case .bottomLeft: (fx, fy) = (0, 1)
    case .bottom: (fx, fy) = (0.5, 1)
    case .bottomRight: (fx, fy) = (1, 1)
    }
    let w = Double(image.extent.width.rounded()), h = Double(image.extent.height.rounded())
    return try place(image, width: width, height: height, left: Int(((Double(width) - w) * fx).rounded()),
                     top: Int(((Double(height) - h) * fy).rounded()), colour: colour)
}

/// The picture on a `width × height` canvas of `colour`, `left` from the left and `top` from the top
/// (negative cuts into it). Extent origin (0, 0).
private func place(_ image: CIImage, width: Int, height: Int, left: Int, top: Int, colour: RGBAColor) throws -> CIImage {
    guard width > 0, height > 0 else { throw CanvasError.nothingLeft }
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    let e = image.extent
    // Core Image's origin is the bottom-left corner: a picture `top` from the top sits at y = H − top − h.
    let moved = image.transformed(by: .init(translationX: CGFloat(left) - e.minX,
                                            y: CGFloat(height - top) - e.height - e.minY))
    let fill = CIColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: colour.alpha,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    return moved.composited(over: CIImage(color: fill).cropped(to: canvas)).cropped(to: canvas)
}
