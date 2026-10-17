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
        let width = image.extent.width, height = image.extent.height
        // Edges are found on a copy at most 1024 pixels long, so 24 MP stays fast.
        let s = min(1, 1024 / max(width, height))
        let small = image.clampedToExtent().transformed(by: .init(scaleX: s, y: s))
            .cropped(to: CGRect(x: 0, y: 0, width: max(1, (width * s).rounded(.down)),
                                height: max(1, (height * s).rounded(.down))))
        guard let p = try? RGBAImage(PipelineRender.cgImage(small)) else { return image }

        func near(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            abs(Int(a.r) - Int(b.r)) <= 8 && abs(Int(a.g) - Int(b.g)) <= 8
                && abs(Int(a.b) - Int(b.b)) <= 8 && abs(Int(a.a) - Int(b.a)) <= 8
        }
        let topLeft = p[0, 0], bottomRight = p[p.width - 1, p.height - 1]
        func row(_ y: Int, _ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            (0..<p.width).allSatisfy { near(p[$0, y], c) }
        }
        var top = 0
        while top < p.height, row(top, topLeft) { top += 1 }
        if top == p.height { return image }
        var bottom = p.height - 1
        while bottom > top, row(bottom, bottomRight) { bottom -= 1 }
        func column(_ x: Int, _ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            (top...bottom).allSatisfy { near(p[x, $0], c) }
        }
        var left = 0
        while left < p.width - 1, column(left, topLeft) { left += 1 }
        var right = p.width - 1
        while right > left, column(right, bottomRight) { right -= 1 }

        // Back to full size, rounding outward so no picture is lost.
        let x0 = (Double(left) / s).rounded(.down), x1 = min(width, (Double(right + 1) / s).rounded(.up))
        let y0 = (Double(top) / s).rounded(.down), y1 = min(height, (Double(bottom + 1) / s).rounded(.up))
        // Core Image's origin is the bottom-left corner.
        return atOrigin(image.cropped(to: CGRect(x: x0, y: height - y1, width: x1 - x0, height: y1 - y0)))
    }
}

public enum CanvasStep {
    /// Runs auto-crop first when `s.autoCropBorders`.
    public static func apply(_ image: CIImage, _ s: CanvasSettings, scale: Double) throws -> CIImage {
        guard s.isOn else { return image }
        let image = s.autoCropBorders ? AutoCropStep.apply(image) : atOrigin(image)
        let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
        func scaled(_ v: Int) -> Int { Int((Double(v) * scale).rounded()) }
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
            let width = max(w, Int((Double(h) * ratio).rounded())), height = max(h, Int((Double(w) / ratio).rounded()))
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
            let b = Int((Double(width) * scale).rounded())
            guard b > 0 else { continue }
            let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
            // Growing a picture always leaves pixels: `place` can't throw here.
            image = (try? place(image, width: w + 2 * b, height: h + 2 * b, left: b, top: b, colour: colour)) ?? image
        }
        return image
    }
}

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
