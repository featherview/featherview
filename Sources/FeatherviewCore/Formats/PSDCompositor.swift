import Foundation

/// Draws a Photoshop file's layer tree, bottom up, at a decode's scale: groups (pass-through or isolated),
/// clipping, layer masks, Blend If, opacity and fill, through `PSDBlend`. Transparent where nothing is drawn.
// shortcut: knockout (knko) is ignored, honour it if a file shows it.
public struct PSDCompositor: Sendable {
    /// Adjusts an image in place; the bytes, one per pixel (nil: all 255), say how much each pixel counts, so
    /// the closure may skip pixels at 0. The compositor mixes the result in by them.
    public typealias Adjust = (inout RGBAImage, [UInt8]?) -> Void
    typealias Point = (x: Int, y: Int)

    let layers: PSDLayers
    let content: @Sendable (PSDLayer, Double) throws -> RGBAImage?
    let adjustment: @Sendable (PSDLayer) -> Adjust?

    /// `content` gives a layer's pixels at a scale: at the layer's `scaledRect(scale:)` top-left, or at the
    /// origin when the image has the scaled canvas's size; nil draws nothing. `adjustment` makes a layer an
    /// adjustment of what lies below it.
    public init(_ layers: PSDLayers,
                content: @escaping @Sendable (PSDLayer, Double) throws -> RGBAImage? = { try $0.channels(scale: $1) },
                adjustment: @escaping @Sendable (PSDLayer) -> Adjust? = { _ in nil }) {
        self.layers = layers
        self.content = content
        self.adjustment = adjustment
    }

    /// The picture at `scale` (≤ 1), `PSDLayers.scaledSize` per side.
    public func render(scale: Double) throws -> RGBAImage {
        let width = PSDLayers.scaledSize(layers.width, scale), height = PSDLayers.scaledSize(layers.height, scale)
        var canvas = RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
        try draw(layers.nodes, onto: &canvas, at: (0, 0), scale)
        return canvas
    }

    /// Draws `nodes`, bottom to top, onto `target`, whose top-left sits at `origin` in the scaled canvas.
    private func draw(_ nodes: [PSDNode], onto target: inout RGBAImage, at origin: Point, _ scale: Double) throws {
        var i = 0
        while i < nodes.count {
            let base = nodes[i]
            var end = i + 1
            while end < nodes.count, nodes[end].clipped { end += 1 }
            let clipped = nodes[i + 1 ..< end]
            i = end
            guard base.visible else { continue }

            if case .group(let group) = base, group.blend == "pass", clipped.isEmpty {
                let weights = try maskValues(group.mask, scale, origin, target.width, target.height)
                if weights == nil, group.opacity == 255 {
                    try draw(group.children, onto: &target, at: origin, scale)
                } else {
                    var copy = target
                    try draw(group.children, onto: &copy, at: origin, scale)
                    Self.mix(&target, copy, weights, Int(group.opacity))
                }
                continue
            }
            // shortcut: an adjustment layer draws in normal mode and ignores layers clipped to it, honour both if a file shows them.
            if case .layer(let layer) = base, let adjust = adjustment(layer) {
                let weights = try maskValues(layer.mask, scale, origin, target.width, target.height)
                var adjusted = target
                adjust(&adjusted, weights)
                Self.mix(&target, adjusted, weights, (Int(layer.opacity) * Int(layer.fill) + 127) / 255)
                continue
            }

            guard case (var image, let at)? = try element(base, scale) else { continue }
            if !clipped.isEmpty {
                // Clipped layers blend onto the base as if it were opaque, then take its alpha.
                let alphas = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
                for p in alphas.indices { image.pixels[p * 4 + 3] = 255 }
                for node in clipped { try draw([node], onto: &image, at: at, scale) }
                for p in alphas.indices { image.pixels[p * 4 + 3] = alphas[p] }
            }
            let local = (x: at.x - origin.x, y: at.y - origin.y)
            var mask = try maskValues(base.mask, scale, at, image.width, image.height)
            if let blendIf = base.blendIf { mask = Self.apply(blendIf, image, at: local, over: target, to: mask) }
            PSDBlend.composite(PSDBlend.mode(base.blend) ?? .normal, onto: &target, layer: image, at: local, alpha: mask,
                               opacity: Float(base.opacity) / 255, fill: Float(base.fill) / 255)
        }
    }

    /// A layer's pixels or an isolated group's children drawn onto transparency, and where it sits in the scaled
    /// canvas; nil when there is nothing to draw.
    private func element(_ node: PSDNode, _ scale: Double) throws -> (RGBAImage, Point)? {
        let width = PSDLayers.scaledSize(layers.width, scale), height = PSDLayers.scaledSize(layers.height, scale)
        switch node {
        case .layer(let layer):
            guard let image = try content(layer, scale) else { return nil }
            if image.width == width, image.height == height { return (image, (0, 0)) }
            let rect = layer.scaledRect(scale: scale)
            return (image, (rect.left, rect.top))
        case .group(let group):
            var image = RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
            try draw(group.children, onto: &image, at: (0, 0), scale)
            return (image, (0, 0))
        }
    }

    /// `mask`'s values over a `width × height` area at `origin` in the scaled canvas, its default colour outside
    /// its rect; nil without a mask or with a disabled one. The rect is on the canvas whether or not the mask is
    /// marked relative to the layer: that flag says it moves with the layer.
    private func maskValues(_ mask: PSDMask?, _ scale: Double, _ origin: Point, _ width: Int, _ height: Int) throws -> [UInt8]? {
        guard let mask, !mask.disabled else { return nil }
        let (rect, pixels) = try mask.pixels(scale: scale)
        var out = [UInt8](repeating: mask.defaultColour, count: width * height)
        let x0 = max(rect.left, origin.x), x1 = min(rect.right, origin.x + width)
        let y0 = max(rect.top, origin.y), y1 = min(rect.bottom, origin.y + height)
        guard x0 < x1, y0 < y1 else { return out }
        let maskWidth = rect.right - rect.left
        for y in y0..<y1 {
            let from = (y - rect.top) * maskWidth - rect.left, to = (y - origin.y) * width - origin.x
            out.replaceSubrange(to + x0 ..< to + x1, with: pixels[from + x0 ..< from + x1])
        }
        return out
    }

    /// `mask` (nil: all 255) lowered where `image`'s pixel, or the backdrop under it in `target`, lies outside
    /// the Blend If ranges, with the split feather between the inner and outer values.
    private static func apply(_ blendIf: PSDBlendIf, _ image: RGBAImage, at: Point, over target: RGBAImage,
                              to mask: [UInt8]?) -> [UInt8] {
        var out = mask ?? [UInt8](repeating: 255, count: image.width * image.height)
        func factor(_ v: Int, _ r: [UInt8]) -> Float {
            let (bl, bh, wl, wh) = (Int(r[0]), Int(r[1]), Int(r[2]), Int(r[3]))
            if v < bl || v > wh { return 0 }
            if v < bh { return Float(v - bl) / Float(bh - bl) }
            if v > wl { return Float(wh - v) / Float(wh - wl) }
            return 1
        }
        func values(_ p: ArraySlice<UInt8>) -> [Int] {
            let (r, g, b) = (Int(p[p.startIndex]), Int(p[p.startIndex + 1]), Int(p[p.startIndex + 2]))
            return [(30 * r + 59 * g + 11 * b + 50) / 100, r, g, b]
        }
        let ranges = [blendIf.gray, blendIf.red, blendIf.green, blendIf.blue]
        for y in 0..<image.height {
            let ty = y + at.y
            guard ty >= 0, ty < target.height else { continue }
            for x in 0..<image.width {
                let tx = x + at.x, p = y * image.width + x
                guard tx >= 0, tx < target.width, out[p] > 0 else { continue }
                let source = values(image.pixels[p * 4 ..< p * 4 + 4])
                let t = (ty * target.width + tx) * 4, backdrop = values(target.pixels[t ..< t + 4])
                var f: Float = 1
                for k in 0..<4 { f *= factor(source[k], ranges[k].source) * factor(backdrop[k], ranges[k].backdrop) }
                out[p] = UInt8((Float(out[p]) * f).rounded())
            }
        }
        return out
    }

    /// Moves each pixel of `target` toward `other`'s (same size) by its weight (nil: 255) × `opacity` (0…255),
    /// in premultiplied colour, so a transparent pixel adds no colour.
    private static func mix(_ target: inout RGBAImage, _ other: RGBAImage, _ weights: [UInt8]?, _ opacity: Int) {
        let count = target.width * target.height
        other.pixels.withUnsafeBufferPointer { src in
            target.pixels.withUnsafeMutableBufferPointer { dst in
                for p in 0..<count {
                    let t = (weights.map { Int($0[p]) } ?? 255) * opacity  // 0…255²
                    if t == 0 { continue }
                    let i = p * 4
                    if t == 65_025 {
                        for c in 0..<4 { dst[i + c] = src[i + c] }
                        continue
                    }
                    let a0 = Int(dst[i + 3]) * (65_025 - t), a1 = Int(src[i + 3]) * t, ao = a0 + a1
                    for c in 0..<3 { dst[i + c] = ao == 0 ? 0 : UInt8((Int(dst[i + c]) * a0 + Int(src[i + c]) * a1 + ao / 2) / ao) }
                    dst[i + 3] = UInt8((ao + 32_512) / 65_025)
                }
            }
        }
    }
}

private extension PSDNode {
    var visible: Bool { switch self { case .layer(let l): l.visible; case .group(let g): g.visible } }
    var clipped: Bool { switch self { case .layer(let l): l.clipped; case .group(let g): g.clipped } }
    var mask: PSDMask? { switch self { case .layer(let l): l.mask; case .group(let g): g.mask } }
    var blendIf: PSDBlendIf? { switch self { case .layer(let l): l.blendIf; case .group(let g): g.blendIf } }
    var blend: String { switch self { case .layer(let l): l.blend; case .group(let g): g.blend } }
    var opacity: UInt8 { switch self { case .layer(let l): l.opacity; case .group(let g): g.opacity } }
    var fill: UInt8 { switch self { case .layer(let l): l.fill; case .group: 255 } }
}
