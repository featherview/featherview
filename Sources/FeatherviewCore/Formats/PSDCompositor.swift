import CoreGraphics
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
    let vectorMask: @Sendable ([String: Data], UInt8, Double, Double) throws -> (rect: PSDRect, pixels: [UInt8])?

    /// Test hook: the most pixels a working canvas (the picture or a group's; a copy for a mix matches its target) had in this task.
    @TaskLocal static var largestCanvas: OSAllocatedUnfairLock<Int>?
    static func canvas(_ width: Int, _ height: Int) -> RGBAImage {
        largestCanvas?.withLock { $0 = max($0, width * height) }
        return RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    /// Test hook: the bytes of canvases, copies, layer images and masks a render holds, now and at most, in this task.
    @TaskLocal static var liveBytes: OSAllocatedUnfairLock<(now: Int, peak: Int)>?
    static func hold(_ bytes: Int) { liveBytes?.withLock { $0.now += bytes; $0.peak = max($0.peak, $0.now) } }

    /// `content` gives a layer's pixels at a scale: at the layer's `scaledRect(scale:)` top-left, or at the
    /// origin when the image has the scaled canvas's size; nil draws nothing. `adjustment` makes a layer an
    /// adjustment of what lies below it. `vectorMask` gives the vector mask of a group's or adjustment layer's
    /// blocks at a density, feather and scale (0 outside its rect); `content` cuts other layers by theirs.
    public init(_ layers: PSDLayers,
                content: @escaping @Sendable (PSDLayer, Double) throws -> RGBAImage? = { try $0.channels(scale: $1) },
                adjustment: @escaping @Sendable (PSDLayer) -> Adjust? = { _ in nil },
                vectorMask: @escaping @Sendable ([String: Data], UInt8, Double, Double) throws -> (rect: PSDRect, pixels: [UInt8])? = { _, _, _, _ in nil }) {
        self.layers = layers
        self.content = content
        self.adjustment = adjustment
        self.vectorMask = vectorMask
    }

    /// The most pixels of a picture `ImageDecoder` draws from layers (256 MB a canvas); a larger decode draws smaller.
    /// Task-local so a test can lower it.
    @TaskLocal static var maxPixels = 1 << 26

    /// The most bytes a render may hold at once, with the decoded copy of its picture. Task-local so a test can lower it.
    // shortcut: counted from the layer tree (`held`) with every layer image and copy as large as the working canvas;
    // patterns and channel reads aside. Measure a file's real peak if one goes over.
    @TaskLocal static var memoryBudget = 512 << 20

    /// The most pixels the working canvas may have for the render, the canvases it holds at once (`held`) and the
    /// decoded copy of its picture to stay within `memoryBudget`.
    public var budgetPixels: Int { Self.memoryBudget / (4 + max(held(layers.nodes, 1), 4)) }

    /// The picture at `scale` (≤ 1), `PSDLayers.scaledSize` per side.
    public func render(scale: Double) throws -> RGBAImage { try render(scale: scale, maxPixels: min(1 << 24, budgetPixels)) }

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
        var canvas = [Self.canvas(fineWidth, fineHeight)]
        Self.hold(canvas[0].pixels.count)
        defer { Self.hold(-canvas[0].pixels.count) }
        try draw(layers.nodes, onto: &canvas, at: (0, 0), fine)
        return fineWidth == width && fineHeight == height ? canvas[0] : Self.reduce(canvas[0], width, height)
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

    /// Draws `nodes`, bottom to top, onto each of `targets` (one size), whose top-left sits at `origin` in the scaled
    /// canvas. What doesn't depend on the backdrop (a layer's pixels and masks, a group drawn isolated) is made once
    /// for all targets, so a pass-through group's layers, drawn both passed through and isolated, are read once.
    private func draw(_ nodes: [PSDNode], onto targets: inout [RGBAImage], at origin: Point, _ scale: Double) throws {
        guard let first = targets.first else { return }
        let width = first.width, height = first.height, area = width * height, m = targets.count
        var i = 0
        while i < nodes.count {
            let base = nodes[i]
            var end = i + 1
            while end < nodes.count, nodes[end].clipped { end += 1 }
            let clipped = nodes[i + 1 ..< end]
            i = end
            guard base.visible else { continue }

            // Below full fill opacity a pass-through group of pixel layers mixes, by its fill, its layers passed through
            // (themselves at that fill) with them drawn isolated at that fill, as Photoshop's composites show.
            // shortcut: with adjustment layers in it, it draws isolated (which the composites show when one sits over
            // a pixel layer); pass them through within its content if a file shows otherwise.
            if case .group(let group) = base, group.blend == "pass", group.fill < 255, clipped.isEmpty, !adjusts(group.children) {
                let f = Int(group.fill)
                // Its content first, then each target with its layers passed through.
                var drawn = [Self.canvas(width, height)] + targets
                Self.hold(4 * area * (m + 1))
                defer { Self.hold(-4 * area * (m + 1)) }
                try draw(group.children, onto: &drawn, at: origin, scale)
                let content = drawn[0]
                let weights = try masks(base, scale, origin, width, height)
                Self.hold(weights?.count ?? 0)
                defer { Self.hold(-(weights?.count ?? 0)) }
                for k in targets.indices {
                    Self.hold(4 * area)
                    defer { Self.hold(-4 * area) }
                    var mixed = targets[k]
                    Self.mix(&mixed, drawn[k + 1], nil, f)
                    drawn[k + 1] = targets[k]  // the passed copy goes; the isolated draw takes its place
                    PSDBlend.composite(.normal, onto: &drawn[k + 1], layer: content, at: (0, 0), fill: Float(f) / 255)
                    Self.mix(&mixed, drawn[k + 1], nil, f)
                    drawn[k + 1] = content
                    Self.mix(&targets[k], mixed, weights, Int(group.opacity))
                }
                continue
            }
            // Below full fill opacity (with adjustments) a pass-through group draws isolated, as Photoshop's composites show.
            if case .group(let group) = base, group.blend == "pass", group.fill == 255 {
                var weights = try masks(base, scale, origin, width, height)
                Self.hold(weights?.count ?? 0)
                defer { Self.hold(-(weights?.count ?? 0)) }
                if !clipped.isEmpty {
                    // As a clipping base it still passes through, but only where it has content of its own (an
                    // adjustment alone has none), with the clipped layers over it; its layers bring their own alpha.
                    var drawn = [Self.canvas(width, height)] + targets
                    Self.hold(4 * area * (m + 1) + 2 * area)  // and the alphas and weights below
                    defer { Self.hold(-(4 * area * (m + 1) + 2 * area)) }
                    try draw(group.children, onto: &drawn, at: origin, scale)
                    let content = drawn.removeFirst()
                    for node in clipped { try draw([node], onto: &drawn, at: origin, scale) }
                    let alphas = stride(from: 3, to: content.pixels.count, by: 4).map { content.pixels[$0] > 0 ? UInt8(255) : 0 }
                    weights = weights.map { zip($0, alphas).map { UInt8((Int($0) * Int($1) + 127) / 255) } } ?? alphas
                    for k in targets.indices { Self.mix(&targets[k], drawn[k], weights, Int(group.opacity)) }
                } else if weights == nil, group.opacity == 255 {
                    try draw(group.children, onto: &targets, at: origin, scale)
                } else {
                    var copies = targets
                    Self.hold(4 * area * m)
                    defer { Self.hold(-4 * area * m) }
                    try draw(group.children, onto: &copies, at: origin, scale)
                    for k in targets.indices { Self.mix(&targets[k], copies[k], weights, Int(group.opacity)) }
                }
                continue
            }
            // shortcut: an adjustment layer draws in normal mode, honour its blend mode if a file shows it.
            if case .layer(let layer) = base, let adjust = adjustment(layer) {
                let weights = try masks(base, scale, origin, width, height)
                var adjusted = targets
                var mixed: [[UInt8]?] = []
                Self.hold(area + 5 * area * m)  // the weights, then a copy and weights per target
                defer { Self.hold(-(area + 5 * area * m)) }
                for k in targets.indices {
                    adjust(&adjusted[k], weights)
                    mixed.append(layer.blendIf.map { Self.apply($0, adjusted[k], at: (0, 0), over: targets[k], to: weights) } ?? weights)
                }
                // Layers clipped to it draw over what it adjusted, inside its mask.
                for node in clipped { try draw([node], onto: &adjusted, at: origin, scale) }
                for k in targets.indices {
                    Self.mix(&targets[k], adjusted[k], mixed[k], (Int(layer.opacity) * Int(layer.fill) + 127) / 255)
                }
                continue
            }

            guard case (var image, let at)? = try element(base, scale) else { continue }
            let bytes = image.pixels.count + 2 * image.width * image.height  // and the alphas or the mask, and Blend If's
            Self.hold(bytes)
            defer { Self.hold(-bytes) }
            var fill = Float(base.fill) / 255
            if !clipped.isEmpty {
                // Clipped layers blend onto the base as if its alpha were its fill, then take its alpha: fill
                // fades only the base's own pixels.
                // shortcut: the base's fill then acts as plain alpha in the modes that apply fill inside the blend, honour it if a file shows it.
                let alphas = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
                for p in alphas.indices { image.pixels[p * 4 + 3] = base.fill }
                var images = [consume image]
                for node in clipped { try draw([node], onto: &images, at: at, scale) }
                image = images.removeLast()
                for p in alphas.indices { image.pixels[p * 4 + 3] = UInt8((Int(image.pixels[p * 4 + 3]) * Int(alphas[p]) + 127) / 255) }
                fill = 1
            }
            let local = (x: at.x - origin.x, y: at.y - origin.y)
            // A layer's vector mask is in its content already.
            let mask = try base.isGroup ? masks(base, scale, at, image.width, image.height)
                                        : maskValues(base.mask, scale, at, image.width, image.height)
            let mode = PSDBlend.mode(base.blend) ?? .normal
            for k in targets.indices {
                let alpha = base.blendIf.map { Self.apply($0, image, at: local, over: targets[k], to: mask) } ?? mask
                if mode == .normal, base.blocks["TySh"] != nil {
                    Self.text(&targets[k], image, at: local, alpha: alpha, Float(base.opacity) / 255 * fill)
                } else {
                    PSDBlend.composite(mode, onto: &targets[k], layer: image, at: local, alpha: alpha, opacity: Float(base.opacity) / 255, fill: fill)
                }
            }
        }
    }

    /// Bytes per pixel of the working canvas that `draw(nodes)` onto `m` targets holds at most beside them, as
    /// `hold` counts: 4 for a canvas, a copy or a layer image, 1 for a mask; a layer image while it's made (a fill
    /// layer, its vector mask and its placed copy) 9.
    func held(_ nodes: [PSDNode], _ m: Int) -> Int {
        var peak = 0, i = 0
        while i < nodes.count {
            let base = nodes[i]
            var end = i + 1
            while end < nodes.count, nodes[end].clipped { end += 1 }
            let clipped = nodes[i + 1 ..< end]
            i = end
            guard base.visible else { continue }
            func clips(_ n: Int) -> Int { clipped.map { held([$0], n) }.max() ?? 0 }
            let cost: Int
            switch base {
            case .group(let group) where group.blend == "pass" && group.fill < 255 && clipped.isEmpty && !adjusts(group.children):
                cost = 4 * (m + 1) + max(held(group.children, m + 1), 1 + 4)
            case .group(let group) where group.blend == "pass" && group.fill == 255 && !clipped.isEmpty:
                cost = 1 + 4 * (m + 1) + 2 + max(held(group.children, m + 1), clips(m))
            case .group(let group) where group.blend == "pass" && group.fill == 255:
                // Drawn straight onto the targets without a mask or opacity, else onto copies.
                let masked = group.mask.map { !$0.disabled } ?? false || group.blocks["vmsk"] != nil || group.blocks["vsms"] != nil
                cost = (masked || group.opacity < 255 ? 1 + 4 * m : 0) + held(group.children, m)
            case .layer(let layer) where adjustment(layer) != nil:
                cost = 1 + 5 * m + clips(m)
            case .layer:
                cost = max(9, 6 + clips(1))
            case .group(let group):
                cost = max(4 + held(group.children, 1), 6 + clips(1))
            }
            peak = max(peak, cost)
        }
        return peak
    }

    /// Whether any of `nodes`, or of their groups' children, is an adjustment layer.
    private func adjusts(_ nodes: [PSDNode]) -> Bool {
        nodes.contains {
            switch $0 {
            case .layer(let layer): adjustment(layer) != nil
            case .group(let group): adjusts(group.children)
            }
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
            var image = [Self.canvas(width, height)]
            Self.hold(image[0].pixels.count)
            defer { Self.hold(-image[0].pixels.count) }
            try draw(group.children, onto: &image, at: (0, 0), scale)
            return (image[0], (0, 0))
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
        guard let vector = try vectorMask(node.blocks, node.vectorDensity, node.vectorFeather, scale) else { return mask }
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

    /// 8-bit values in a 1.45 gamma (0…1), and back from 65,536 steps of it.
    private static let textGamma = (encode: (0...255).map { pow(Float($0) / 255, 1.45) },
                                    decode: (0...65_535).map { UInt8((pow(Float($0) / 65_535, 1 / 1.45) * 255).rounded()) })

    /// Source-over of a text layer (straight alpha, `mask` layer-sized or nil, times `opacity`) onto `target` at `at`, its
    /// colours mixed in a 1.45 gamma: Photoshop's default for text, which its composites show.
    private static func text(_ target: inout RGBAImage, _ layer: RGBAImage, at: Point, alpha mask: [UInt8]?, _ opacity: Float) {
        let encode = Self.textGamma.encode, decode = Self.textGamma.decode
        let x0 = max(0, -at.x), x1 = min(layer.width, target.width - at.x)
        let y0 = max(0, -at.y), y1 = min(layer.height, target.height - at.y)
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            for x in x0..<x1 {
                let p = y * layer.width + x, s = p * 4, d = ((y + at.y) * target.width + x + at.x) * 4
                let a = Float(layer.pixels[s + 3]) / 255 * (mask.map { Float($0[p]) / 255 } ?? 1) * opacity
                guard a > 0 else { continue }
                let b = Float(target.pixels[d + 3]) / 255, out = a + b * (1 - a)
                for c in 0..<3 {
                    let mixed = (a * encode[Int(layer.pixels[s + c])] + b * (1 - a) * encode[Int(target.pixels[d + c])]) / out
                    target.pixels[d + c] = decode[Int(mixed * 65_535 + 0.5)]
                }
                target.pixels[d + 3] = UInt8((out * 255).rounded())
            }
        }
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
    var vectorFeather: Double { switch self { case .layer(let l): l.vectorFeather; case .group(let g): g.vectorFeather } }
    var isGroup: Bool { if case .group = self { true } else { false } }
}

public extension PSDCompositor {
    /// Tagged blocks that make a layer an adjustment (`PSDAdjustments`), the first one present deciding. CgEd comes before
    /// brit: Photoshop keeps Brightness/Contrast's settings in CgEd and writes brit as zeros beside it.
    static let adjustmentKeys = ["levl", "curv", "CgEd", "brit", "hue2", "blnc", "blwh", "mixr", "expA", "vibA", "phfl",
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
        let rgb = layers.profile.flatMap { CGColorSpace(iccData: $0 as CFData) }.flatMap { $0.model == .rgb ? $0 : nil }

        return PSDCompositor(layers, content: { layer, scale in
            let width = PSDLayers.scaledSize(canvas.width, scale), height = PSDLayers.scaledSize(canvas.height, scale)
            // A stroked shape's stored pixels hold its stroke, which can lie outside the path: they draw as they are.
            let stroked = layer.blocks["vstk"] != nil
            if !stroked, let fill = try PSDFills.content(layer, canvas: canvas, patterns: patterns, scale: scale, rgb: rgb) {
                guard fill.width > 0, fill.height > 0 else { return nil }
                if fill.width == width, fill.height == height { return fill }
                // Cut by a vector mask, the fill covers only the mask's rect: placed on the canvas here, since the
                // compositor puts anything smaller at the layer's own rect.
                guard let rect = try PSDFills.vectorMask(layer, canvas: canvas, scale: scale)?.rect else { return nil }
                PSDCompositor.hold(fill.pixels.count + width * height * 4)
                defer { PSDCompositor.hold(-(fill.pixels.count + width * height * 4)) }
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
        }, vectorMask: { blocks, density, feather, scale in
            try PSDFills.vectorMask(blocks, density: density, feather: feather, canvas: canvas, scale: scale).map { ($0.rect, $0.pixels) }
        })
    }
}
