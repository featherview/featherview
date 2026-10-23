import CoreGraphics
import CoreImage
import Foundation

/// Moves the image's extent back to origin (0, 0), which every step relies on.
private func atOrigin(_ image: CIImage) -> CIImage {
    let e = image.extent
    return e.origin == .zero ? image : image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
}

/// Where along one axis an anchor sits: the near edge (left/top), the middle, or the far edge.
private enum Side { case near, middle, far }

private extension ImageAnchor {
    var horizontal: Side {
        switch self {
        case .topLeft, .left, .bottomLeft: .near
        case .top, .center, .bottom: .middle
        case .topRight, .right, .bottomRight: .far
        }
    }

    var vertical: Side {
        switch self {
        case .topLeft, .top, .topRight: .near
        case .left, .center, .right: .middle
        case .bottomLeft, .bottom, .bottomRight: .far
        }
    }
}

public enum CropStep {
    /// `scale` multiplies every pixel value (1 for output, < 1 for the preview).
    public static func apply(_ image: CIImage, _ s: CropSettings, scale: Double) -> CIImage {
        guard s.isOn else { return image }
        let picture = atOrigin(image)
        let total = (w: Int(picture.extent.width), h: Int(picture.extent.height))
        // Clamped first: presets aren't trusted.
        let px = { (v: Int) in clampedPixels(Double(v) * scale) }
        // A set length stays at least 1 pixel in the preview: 0 would mean "to the edge".
        let length = { (v: Int) in v > 0 ? max(1, px(v)) : 0 }

        /// Start and length along one axis, measured from the near edge (left, or top).
        func place(_ side: Side, offset: Int, length: Int, total: Int) -> (start: Int, length: Int) {
            let length = length > 0 ? length : (side == .middle ? total : total - offset)
            return switch side {
            case .near: (offset, length)
            case .middle: ((total - length) / 2 + offset, length)
            case .far: (total - offset - length, length)
            }
        }
        let x = place(s.anchor.horizontal, offset: px(s.x), length: length(s.width), total: total.w)
        let y = place(s.anchor.vertical, offset: px(s.y), length: length(s.height), total: total.h)
        // Core Image's y grows upwards: a rectangle `y.start` below the top sits at H − start − length.
        let rect = CGRect(x: x.start, y: total.h - y.start - y.length, width: x.length, height: y.length)
            .intersection(picture.extent)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return picture }
        return atOrigin(picture.cropped(to: rect))
    }
}

public enum ResizeStep {
    /// The output size for an image of `size` (the preview passes its own size and `scale`).
    public static func targetSize(for size: CGSize, _ s: ResizeSettings, scale: Double) -> CGSize {
        guard s.isOn, size.width > 0, size.height > 0 else { return size }
        let w = Double(size.width), h = Double(size.height)
        var target: (w: Double, h: Double)
        switch s.mode {
        case .widthHeight:
            let tw = s.width.map { Double($0) * scale }, th = s.height.map { Double($0) * scale }
            switch (tw, th) {
            case let (tw?, th?): target = s.keepAspect ? (w * min(tw / w, th / h), h * min(tw / w, th / h)) : (tw, th)
            case let (tw?, nil): target = (tw, s.keepAspect ? h * tw / w : h)
            case let (nil, th?): target = (s.keepAspect ? w * th / h : w, th)
            case (nil, nil): return size
            }
        case .longestSide, .shortestSide:
            let f = Double(s.side) * scale / (s.mode == .longestSide ? max(w, h) : min(w, h))
            target = (w * f, h * f)
        case .megapixels:
            let f = (max(0, s.megapixels) * 1_000_000 * scale * scale / (w * h)).squareRoot()
            target = (w * f, h * f)
        case .percent:
            target = (w * s.percentWidth / 100, h * (s.keepAspect ? s.percentWidth : s.percentHeight) / 100)
        }
        // At most what the own decoders accept (65,536 a side, 2²⁸ pixels), aspect kept: larger can't render.
        // At least 1 pixel a side first, so a side of 0 or less can't skip the cap on the other.
        target = (max(1, target.w), max(1, target.h))
        if target.w.isFinite, target.h.isFinite {
            let side = min(1, 65536 / max(target.w, target.h))
            target = (target.w * side, target.h * side)
            let area = min(1, (Double(maxOwnPixels) / (target.w * target.h)).squareRoot())
            // Rounded down, so rounding below can't push it back over.
            if area < 1 { target = ((target.w * area).rounded(.down), (target.h * area).rounded(.down)) }
        }
        // NaN or ±∞ (a broken setting) becomes 1 pixel or keeps the input size below, never a crash.
        let round = { (v: Double) in v.isFinite ? max(1, v.rounded()) : (v > 0 ? .infinity : 1) }
        let result = CGSize(width: round(target.w), height: round(target.h))
        if !result.width.isFinite || !result.height.isFinite { return size }
        if s.dontEnlarge, result.width > size.width || result.height > size.height { return size }
        if s.dontShrink, result.width < size.width || result.height < size.height { return size }
        return result
    }

    /// `originalSize`: the upright size before a smaller decode (`decodeLimit`, the preview). The target comes
    /// from it at full size, times `scale`, so the decode's own rounding can't change the output size.
    public static func apply(_ image: CIImage, _ s: ResizeSettings, scale: Double, originalSize: CGSize? = nil) -> CIImage {
        guard s.isOn else { return image }
        let picture = atOrigin(image)
        let size = picture.extent.size
        var target = targetSize(for: originalSize ?? size, s, scale: originalSize == nil ? scale : 1)
        if originalSize != nil, scale != 1 {
            // The preview: the full-size target (its caps and rounding) scaled down, as the output gets it.
            target = CGSize(width: max(1, (target.width * scale).rounded()), height: max(1, (target.height * scale).rounded()))
        }
        guard target != size else { return picture }
        let sx = target.width / size.width, sy = target.height / size.height
        // Clamped first, so the resample doesn't pull transparency in at the edges.
        let scaled = picture.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: sy,
            kCIInputAspectRatioKey: sx / sy,
        ])
        // Lanczos can leave a fractional row: crop to exactly the target.
        return scaled.cropped(to: CGRect(origin: .zero, size: target))
    }

    /// The largest pixel size a decode may be limited to before the pipeline runs, or nil when
    /// the full image is needed (crop on, or a mode that isn't a plain downscale). Used by Task 8
    /// to keep the old fast path (decode at the target size) for the common "longest side" case;
    /// pass `originalSize` to `apply` then, so the output keeps the exact size.
    public static func decodeLimit(_ settings: BatchSettings, originalSize: CGSize) -> Int? {
        let s = settings.resize
        guard s.isOn, !settings.crop.isOn, s.mode == .longestSide else { return nil }
        let target = targetSize(for: originalSize, s, scale: 1)
        let long = Int(max(target.width, target.height))
        return long < Int(max(originalSize.width, originalSize.height)) ? long : nil
    }
}

public enum OrientationStep {
    public static func apply(_ image: CIImage, _ s: OrientationSettings) -> CIImage {
        guard s.isOn else { return image }
        // Exact matrices (no rotation angles), so the extent stays whole pixels. Core Image's y grows
        // upwards: a clockwise quarter turn in the picture maps (x, y) to (y, −x).
        var t = CGAffineTransform.identity
        switch s.rotate {
        case .none: break
        case .left: t = t.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
        case .right: t = t.concatenating(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0))
        }
        if s.flipHorizontal { t = t.concatenating(CGAffineTransform(scaleX: -1, y: 1)) }
        if s.flipVertical { t = t.concatenating(CGAffineTransform(scaleX: 1, y: -1)) }
        return atOrigin(image.transformed(by: t))
    }
}
