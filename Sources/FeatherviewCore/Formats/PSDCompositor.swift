import Foundation
import os

/// Draws a Photoshop file's layer tree, bottom up, for a decode's scale: groups (pass-through or isolated),
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
    let vectorMask: @Sendable ([String: Data], UInt8, Double) throws -> (rect: PSDRect, pixels: [UInt8])?

    /// Test hook: the most pixels a working canvas (the picture or a group's; a copy for a mix matches its target) had in this task.
    @TaskLocal static var largestCanvas: OSAllocatedUnfairLock<Int>?
    static func canvas(_ width: Int, _ height: Int) -> RGBAImage {
        largestCanvas?.withLock { $0 = max($0, width * height) }
        return RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    /// `content` gives a layer's pixels at a scale: at the layer's `scaledRect(scale:)` top-left, or at the
    /// origin when the image has the scaled canvas's size; nil draws nothing. `adjustment` makes a layer an
    /// adjustment of what lies below it. `vectorMask` gives the vector mask of a group's or adjustment layer's
    /// blocks at a density and scale (0 outside its rect); `content` cuts other layers by theirs.
    public init(_ layers: PSDLayers,
                content: @escaping @Sendable (PSDLayer, Double) throws -> RGBAImage? = { try $0.channels(scale: $1) },
                adjustment: @escaping @Sendable (PSDLayer) -> Adjust? = { _ in nil },
                vectorMask: @escaping @Sendable ([String: Data], UInt8, Double) throws -> (rect: PSDRect, pixels: [UInt8])? = { _, _, _ in nil }) {
        self.layers = layers
        self.content = content
        self.adjustment = adjustment
        self.vectorMask = vectorMask
    }

    /// The most pixels of a picture `ImageDecoder` draws from layers (256 MB a canvas); larger ones go to ImageIO.
    static let maxPixels = 1 << 26

    /// The picture at `scale` (≤ 1), `PSDLayers.scaledSize` per side.
    public func render(scale: Double) throws -> RGBAImage { try render(scale: scale, maxPixels: 1 << 24) }

    /// Composites at twice `scale` per side (at most full size, and at most `maxPixels` unless `scale` itself
    /// needs more), then reduces once: layers reduced before compositing go wrong where an alpha edge cuts a cell
    /// over a backdrop that varies inside it, and twice the scale keeps that small while every working canvas
    /// stays near the decode size.
    // shortcut: such cells can still be off a little, composite in full-size bands if a file shows it.
    func render(scale: Double, maxPixels: Int) throws -> RGBAImage {
        let width = PSDLayers.scaledSize(layers.width, scale), height = PSDLayers.scaledSize(layers.height, scale)
        let cap = (Double(maxPixels) / Double(layers.width * layers.height)).squareRoot()
        let fine = max(min(scale, 1), min(1, 2 * scale, cap))
        let fineWidth = PSDLayers.scaledSize(layers.width, fine), fineHeight = PSDLayers.scaledSize(layers.height, fine)
        var canvas = Self.canvas(fineWidth, fineHeight)
        try draw(layers.nodes, onto: &canvas, at: (0, 0), fine)
        return fineWidth == width && fineHeight == height ? canvas : Self.reduce(canvas, width, height)
    }

    /// `image` area-averaged to `width × height` through `PSDLayers.cell`, colour weighted by alpha.
    private static func reduce(_ image: RGBAImage, _ width: Int, _ height: Int) -> RGBAImage {
        let columns = (0..<image.width).map { PSDLayers.cell($0, image.width, width) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Bands of output rows on all cores; each sums the source rows that fall in its rows.
        let bands = min(height, ProcessInfo.processInfo.activeProcessorCount * 2)
        image.pixels.withUnsafeBufferPointer { src in
            pixels.withUnsafeMutableBufferPointer { out in
                // Each band writes only its own output rows; the source is only read.
                nonisolated(unsafe) let src = src.baseAddress!, out = out.baseAddress!
                DispatchQueue.concurrentPerform(iterations: bands) { band in
                    let first = band * height / bands, last = (band + 1) * height / bands
                    var sums = [Int](repeating: 0, count: (last - first) * width * 5)  // R·A, G·A, B·A, A, area
                    sums.withUnsafeMutableBufferPointer { sums in
                        for y in PSDLayers.cellStart(first, image.height, height) ..< PSDLayers.cellStart(last, image.height, height) {
                            let row = (PSDLayers.cell(y, image.height, height) - first) * width
                            for x in 0..<image.width {
                                let i = (y * image.width + x) * 4, o = (row + columns[x]) * 5, a = Int(src[i + 3])
                                sums[o] += Int(src[i]) * a
                                sums[o + 1] += Int(src[i + 1]) * a
                                sums[o + 2] += Int(src[i + 2]) * a
                                sums[o + 3] += a
                                sums[o + 4] += 1
                            }
                        }
                        for p in 0 ..< (last - first) * width {
                            let o = p * 5, alpha = sums[o + 3], area = sums[o + 4], d = (first * width + p) * 4
                            if alpha > 0 { for c in 0..<3 { out[d + c] = UInt8((sums[o + c] + alpha / 2) / alpha) } }
                            out[d + 3] = UInt8((alpha + area / 2) / area)
                        }
                    }
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
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

            // Below full fill opacity a pass-through group draws isolated, as Photoshop's composites show.
            if case .group(let group) = base, group.blend == "pass", group.fill == 255, clipped.isEmpty {
                let weights = try masks(base, scale, origin, target.width, target.height)
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
                let weights = try masks(base, scale, origin, target.width, target.height)
                var adjusted = target
                adjust(&adjusted, weights)
                let mixed = layer.blendIf.map { Self.apply($0, adjusted, at: (0, 0), over: target, to: weights) } ?? weights
                Self.mix(&target, adjusted, mixed, (Int(layer.opacity) * Int(layer.fill) + 127) / 255)
                continue
            }

            guard case (var image, let at)? = try element(base, scale) else { continue }
            var fill = Float(base.fill) / 255
            if !clipped.isEmpty {
                // Clipped layers blend onto the base as if its alpha were its fill, then take its alpha: fill
                // fades only the base's own pixels.
                // shortcut: the base's fill then acts as plain alpha in the modes that apply fill inside the blend, honour it if a file shows it.
                let alphas = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
                for p in alphas.indices { image.pixels[p * 4 + 3] = base.fill }
                for node in clipped { try draw([node], onto: &image, at: at, scale) }
                for p in alphas.indices { image.pixels[p * 4 + 3] = UInt8((Int(image.pixels[p * 4 + 3]) * Int(alphas[p]) + 127) / 255) }
                fill = 1
            }
            let local = (x: at.x - origin.x, y: at.y - origin.y)
            // A layer's vector mask is in its content already.
            var mask = try base.isGroup ? masks(base, scale, at, image.width, image.height)
                                        : maskValues(base.mask, scale, at, image.width, image.height)
            if let blendIf = base.blendIf { mask = Self.apply(blendIf, image, at: local, over: target, to: mask) }
            PSDBlend.composite(PSDBlend.mode(base.blend) ?? .normal, onto: &target, layer: image, at: local, alpha: mask,
                               opacity: Float(base.opacity) / 255, fill: fill)
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
            var image = Self.canvas(width, height)
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
        return Self.place(rect, pixels, outside: mask.dense(mask.defaultColour), origin, width, height)
    }

    /// The layer mask's values times the vector mask's over a `width × height` area at `origin`; nil without either.
    private func masks(_ node: PSDNode, _ scale: Double, _ origin: Point, _ width: Int, _ height: Int) throws -> [UInt8]? {
        let mask = try maskValues(node.mask, scale, origin, width, height)
        guard let vector = try vectorMask(node.blocks, node.vectorDensity, scale) else { return mask }
        let values = Self.place(vector.rect, vector.pixels, outside: 0, origin, width, height)
        guard let mask else { return values }
        return zip(mask, values).map { UInt8((Int($0) * Int($1) + 127) / 255) }
    }

    /// `pixels` (over `rect` in the scaled canvas, `outside` beyond it) over a `width × height` area at `origin`.
    private static func place(_ rect: PSDRect, _ pixels: [UInt8], outside: UInt8, _ origin: Point,
                              _ width: Int, _ height: Int) -> [UInt8] {
        var out = [UInt8](repeating: outside, count: width * height)
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
        // Ranges as Ints, gray, red, green, blue: black low, black high, white low, white high.
        let r = [blendIf.gray, blendIf.red, blendIf.green, blendIf.blue]
        let source = r.flatMap { $0.source.map(Int.init) }, backdrop = r.flatMap { $0.backdrop.map(Int.init) }
        // Blend If off for a channel when both ranges are full; the common case is one channel in use.
        let used = (0..<4).filter { k in [source, backdrop].contains { $0[k * 4 ..< k * 4 + 4] != [0, 0, 255, 255] } }
        guard !used.isEmpty else { return out }
        @inline(__always) func factor(_ v: Int, _ r: UnsafeBufferPointer<Int>, _ k: Int) -> Float {
            let bl = r[k], bh = r[k + 1], wl = r[k + 2], wh = r[k + 3]
            if v < bl || v > wh { return 0 }
            if v < bh { return Float(v - bl) / Float(bh - bl) }
            if v > wl { return Float(wh - v) / Float(wh - wl) }
            return 1
        }
        let x0 = max(0, -at.x), x1 = min(image.width, target.width - at.x)
        let y0 = max(0, -at.y), y1 = min(image.height, target.height - at.y)
        guard x0 < x1, y0 < y1 else { return out }
        source.withUnsafeBufferPointer { src in
            backdrop.withUnsafeBufferPointer { dst in
                image.pixels.withUnsafeBufferPointer { s in
                    target.pixels.withUnsafeBufferPointer { t in
                        out.withUnsafeMutableBufferPointer { out in
                            for y in y0..<y1 {
                                for x in x0..<x1 {
                                    let p = y * image.width + x
                                    guard out[p] > 0 else { continue }
                                    let i = p * 4, j = ((y + at.y) * target.width + x + at.x) * 4
                                    let sr = Int(s[i]), sg = Int(s[i + 1]), sb = Int(s[i + 2])
                                    let br = Int(t[j]), bg = Int(t[j + 1]), bb = Int(t[j + 2])
                                    var f: Float = 1
                                    for k in used {
                                        let sv: Int, bv: Int
                                        switch k {
                                        case 0: sv = (30 * sr + 59 * sg + 11 * sb + 50) / 100; bv = (30 * br + 59 * bg + 11 * bb + 50) / 100
                                        case 1: sv = sr; bv = br
                                        case 2: sv = sg; bv = bg
                                        default: sv = sb; bv = bb
                                        }
                                        f *= factor(sv, src, k * 4) * factor(bv, dst, k * 4)
                                    }
                                    if f < 1 { out[p] = UInt8((Float(out[p]) * f).rounded()) }
                                }
                            }
                        }
                    }
                }
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
    var fill: UInt8 { switch self { case .layer(let l): l.fill; case .group(let g): g.fill } }
    var blocks: [String: Data] { switch self { case .layer(let l): l.blocks; case .group(let g): g.blocks } }
    var vectorDensity: UInt8 { switch self { case .layer(let l): l.vectorDensity; case .group(let g): g.vectorDensity } }
    var isGroup: Bool { if case .group = self { true } else { false } }
}

public extension PSDCompositor {
    /// Tagged blocks that make a layer an adjustment (`PSDAdjustments`).
    static let adjustmentKeys = ["levl", "curv", "brit", "CgEd", "hue2", "blnc", "blwh", "mixr", "expA", "vibA", "phfl",
                                 "nvrt", "thrs", "post", "selc", "grdm"]

    /// The compositor as Photoshop draws `layers`: fill layers (`PSDFills`) and vector masks on any layer, and
    /// adjustment layers (`PSDAdjustments`). Throws `OwnDecodeError.corrupt` when a pattern or adjustment is damaged.
    // shortcut: layer effects (lfx2, lrFX, lmfx), colour lookup (clrL), 3D and video layers draw without them, add one if files show it often.
    static func photoshop(_ layers: PSDLayers) throws -> PSDCompositor {
        let patterns = try PSDFills.patterns(layers)
        // Checked here, since the adjustment hook can't throw: a damaged block fails the whole file.
        func check(_ nodes: [PSDNode]) throws {
            for node in nodes {
                switch node {
                case .layer(let layer):
                    for key in adjustmentKeys { if let data = layer.blocks[key] { _ = try PSDAdjustments.adjustment(key: key, data: data) } }
                case .group(let group): try check(group.children)
                }
            }
        }
        try check(layers.nodes)
        let canvas = (width: layers.width, height: layers.height)

        return PSDCompositor(layers, content: { layer, scale in
            let width = PSDLayers.scaledSize(canvas.width, scale), height = PSDLayers.scaledSize(canvas.height, scale)
            // A stroked shape's stored pixels hold its stroke, which can lie outside the path: they draw as they are.
            let stroked = layer.blocks["vstk"] != nil
            if !stroked, let fill = try PSDFills.content(layer, canvas: canvas, patterns: patterns, scale: scale) {
                guard fill.width > 0, fill.height > 0 else { return nil }
                if fill.width == width, fill.height == height { return fill }
                // Cut by a vector mask, the fill covers only the mask's rect: placed on the canvas here, since the
                // compositor puts anything smaller at the layer's own rect.
                guard let rect = try PSDFills.vectorMask(layer, canvas: canvas, scale: scale)?.rect else { return nil }
                var placed = PSDCompositor.canvas(width, height)
                let x0 = max(0, -rect.left), x1 = min(fill.width, width - rect.left)
                if x0 < x1 {
                    for y in max(0, -rect.top) ..< max(0, min(fill.height, height - rect.top)) {
                        let to = ((rect.top + y) * width + rect.left) * 4, from = y * fill.width * 4
                        placed.pixels.replaceSubrange(to + x0 * 4 ..< to + x1 * 4, with: fill.pixels[from + x0 * 4 ..< from + x1 * 4])
                    }
                }
                return placed
            }
            guard var image = try layer.channels(scale: scale) else { return nil }
            if !stroked, let mask = try PSDFills.vectorMask(layer, canvas: canvas, scale: scale) {
                // The mask is 0 outside its rect (an inverted one covers the canvas).
                let at = layer.scaledRect(scale: scale), r = mask.rect, maskWidth = r.right - r.left
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let cx = at.left + x, cy = at.top + y, i = (y * image.width + x) * 4 + 3
                        let cover = cx >= r.left && cx < r.right && cy >= r.top && cy < r.bottom
                            ? Int(mask.pixels[(cy - r.top) * maskWidth + cx - r.left]) : 0
                        image.pixels[i] = UInt8((Int(image.pixels[i]) * cover + 127) / 255)
                    }
                }
            }
            return image
        }, adjustment: { layer in
            guard let adjust = adjustmentKeys.lazy.compactMap({ key in
                layer.blocks[key].flatMap { try? PSDAdjustments.adjustment(key: key, data: $0) }
            }).first else { return nil }
            return { image, weights in
                let count = image.width * image.height
                image.pixels.withUnsafeMutableBufferPointer { p in
                    for i in 0..<count where p[i * 4 + 3] > 0 && weights.map({ $0[i] > 0 }) ?? true {
                        var c = SIMD3<Float>(Float(p[i * 4]), Float(p[i * 4 + 1]), Float(p[i * 4 + 2])) / 255
                        adjust(&c)
                        let out = (c.clamped(lowerBound: .zero, upperBound: .one) * Float(255)).rounded(.toNearestOrAwayFromZero)
                        p[i * 4] = UInt8(out.x)
                        p[i * 4 + 1] = UInt8(out.y)
                        p[i * 4 + 2] = UInt8(out.z)
                    }
                }
            }
        }, vectorMask: { blocks, density, scale in
            try PSDFills.vectorMask(blocks, density: density, canvas: canvas, scale: scale).map { ($0.rect, $0.pixels) }
        })
    }
}
