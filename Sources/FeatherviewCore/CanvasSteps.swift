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
        // Edges are found on copies at most 1024 pixels long, so 24 MP stays fast. Each small pixel
        // holds the per-channel minimum (or maximum) of the block it covers, not the average, so a
        // thin faint line still shows: a block is border only if its minimum and maximum are both near.
        let s = min(1, 1024 / max(width, height))
        let small = CGRect(x: 0, y: 0, width: (width * s).rounded(.up), height: (height * s).rounded(.up))  // blocks cover every pixel
        let window = 2 * Int((0.5 / s).rounded(.up)) + 1  // reaches a whole block around its centre
        func shrunk(_ filter: String) -> RGBAImage? {
            var copy = image.clampedToExtent()
            if s < 1 {
                copy = copy.applyingFilter(filter, parameters: ["inputWidth": window, "inputHeight": window])
                    // The default downsample blends neighbouring pixels, which pulls a faint minimum back toward the border.
                    .samplingNearest().transformed(by: .init(scaleX: s, y: s), highQualityDownsample: false)
            }
            return try? RGBAImage(PipelineRender.cgImage(copy.cropped(to: small)))
        }
        func strip(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> RGBAImage? {  // full size, y from the top
            try? RGBAImage(PipelineRender.cgImage(image.cropped(to: CGRect(x: x, y: height - y - h, width: w, height: h))))
        }
        // Both passes judge against the exact corner pixels: a shrunk block is border only if its whole
        // range is within 8 of them, so it never runs past an edge the full-size rule would stop at.
        guard let p = shrunk("CIMorphologyRectangleMinimum"), let hi = shrunk("CIMorphologyRectangleMaximum"),
              let topLeft = strip(0, 0, 1, 1)?[0, 0], let bottomRight = strip(width - 1, height - 1, 1, 1)?[0, 0]
        else { return image }

        func near(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            abs(Int(a.r) - Int(b.r)) <= 8 && abs(Int(a.g) - Int(b.g)) <= 8
                && abs(Int(a.b) - Int(b.b)) <= 8 && abs(Int(a.a) - Int(b.a)) <= 8
        }
        func near(_ x: Int, _ y: Int, _ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            near(p[x, y], c) && near(hi[x, y], c)
        }
        func row(_ y: Int, _ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            (0..<p.width).allSatisfy { near($0, y, c) }
        }
        var top = 0
        while top < p.height, row(top, topLeft) { top += 1 }
        if top == p.height { return image }
        var bottom = p.height - 1
        while bottom > top, row(bottom, bottomRight) { bottom -= 1 }
        func column(_ x: Int, _ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            (top...bottom).allSatisfy { near(x, $0, c) }
        }
        var left = 0
        while left < p.width - 1, column(left, topLeft) { left += 1 }
        var right = p.width - 1
        while right > left, column(right, bottomRight) { right -= 1 }

        // Back to full size.
        var x0 = (Double(left) / s).rounded(.down), x1 = min(width, (Double(right + 1) / s).rounded(.up))
        var y0 = (Double(top) / s).rounded(.down), y1 = min(height, (Double(bottom + 1) / s).rounded(.up))
        if s < 1 {
            // A small pixel sees its block and part of its neighbours, so each edge lies within `m` pixels
            // of where the small copies put it: find it exactly on a full-size strip there.
            let m = CGFloat(window) + (1 / s).rounded(.up) + 1
            func first(_ n: Int, _ border: (Int) -> Bool) -> Int { (0..<n).first { !border($0) } ?? n }
            func last(_ n: Int, _ border: (Int) -> Bool) -> Int { (0..<n).last { !border($0) } ?? -1 }
            let (t0, t1) = (max(0, y0 - m), min(height, y0 + m)), (b0, b1) = (max(0, y1 - m), min(height, y1 + m))
            guard let t = strip(0, t0, width, t1 - t0), let b = strip(0, b0, width, b1 - b0)
            else { return image }
            y0 = t0 + CGFloat(first(t.height) { y in (0..<t.width).allSatisfy { near(t[$0, y], topLeft) } })
            y1 = b0 + CGFloat(last(b.height) { y in (0..<b.width).allSatisfy { near(b[$0, y], bottomRight) } } + 1)
            guard y1 > y0 else { return image }
            let (l0, l1) = (max(0, x0 - m), min(width, x0 + m)), (r0, r1) = (max(0, x1 - m), min(width, x1 + m))
            guard let l = strip(l0, y0, l1 - l0, y1 - y0), let r = strip(r0, y0, r1 - r0, y1 - y0) else { return image }
            x0 = l0 + CGFloat(first(l.width) { x in (0..<l.height).allSatisfy { near(l[x, $0], topLeft) } })
            x1 = r0 + CGFloat(last(r.width) { x in (0..<r.height).allSatisfy { near(r[x, $0], bottomRight) } } + 1)
            guard x1 > x0 else { return image }
        }
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
