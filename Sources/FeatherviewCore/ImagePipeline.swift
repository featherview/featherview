import CoreGraphics
import CoreImage
import Foundation

/// What a pipeline run needs besides the settings.
public struct PipelineContext: Sendable {
    public var values: TextValues
    /// Multiplies pixel-valued settings: 1 for output, < 1 for the preview's small decode.
    public var scale: Double = 1
    /// The upright size before a smaller decode (`ResizeStep.decodeLimit`, the preview), so the resize keeps the exact target.
    public var originalSize: CGSize?
    /// Loaded once per batch; the watermark step is skipped without it.
    public var watermark: CIImage?

    public init(values: TextValues, scale: Double = 1, originalSize: CGSize? = nil, watermark: CIImage? = nil) {
        self.values = values; self.scale = scale; self.originalSize = originalSize; self.watermark = watermark
    }
}

/// The batch's per-image operations (spec "Per-image operations"), chained in spec order.
public enum ImagePipeline {
    /// Spec order: crop, resize, rotate/flip, colour, filters, canvas (auto-crop first), border,
    /// text, watermark; renders once; reduces colours last when set.
    /// `hdr` renders with the extended range kept (`PipelineRender.cgImage(_:hdr:)`); reducing colours forces SDR.
    public static func apply(_ image: CGImage, _ settings: BatchSettings, context: PipelineContext,
                             hdr: Bool = false) throws -> CGImage {
        let s = settings, scale = context.scale
        var picture = CIImage(cgImage: image)
        picture = CropStep.apply(picture, s.crop, scale: scale)
        // The full-size input to the resize is the original after the crop.
        let resizeFrom = context.originalSize.map { s.crop.isOn ? CropStep.apply(blank($0), s.crop, scale: 1).extent.size : $0 }
        picture = ResizeStep.apply(picture, s.resize, scale: scale, originalSize: resizeFrom)
        picture = OrientationStep.apply(picture, s.orientation)
        picture = ColourStep.apply(picture, s.colour, scale: scale)
        picture = FilterStep.apply(picture, s.filters, scale: scale)
        picture = try CanvasStep.apply(picture, s.canvas, scale: scale)
        picture = BorderStep.apply(picture, s.border, scale: scale)
        picture = TextStep.apply(picture, s.text, values: context.values, scale: scale)
        if let watermark = context.watermark { picture = WatermarkStep.apply(picture, watermark: watermark, s.watermark) }
        let reduces = s.colour.isOn && s.colour.reduceColours != nil
        let rendered = try PipelineRender.cgImage(picture, hdr: hdr && !reduces)
        guard reduces, let colours = s.colour.reduceColours else { return rendered }
        guard let pixels = RGBAImage(rendered),
              let reduced = ColourQuantizer.reduce(pixels, colours: colours, dither: s.colour.dither).makeCGImage()
        else { throw EncodeError.failed }
        return reduced
    }

    /// The output's size for an input of `size`, from the steps that change it, without rendering the image.
    /// Auto-crop isn't counted (it needs the pixels): with it on, this is the most the output can be.
    public static func outputSize(for size: CGSize, _ s: BatchSettings, values: TextValues) throws -> CGSize {
        var picture = CropStep.apply(blank(size), s.crop, scale: 1)
        picture = ResizeStep.apply(picture, s.resize, scale: 1)
        picture = OrientationStep.apply(picture, s.orientation)
        var canvas = s.canvas
        canvas.autoCropBorders = false
        picture = try CanvasStep.apply(picture, canvas, scale: 1)
        picture = BorderStep.apply(picture, s.border, scale: 1)
        var result = picture.extent.size
        if s.text.isOn, s.text.placement != .inImage, result.width > 0, result.height > 0 {
            // The strip is a share of the image: measured on a copy at most 1024 px a side, never a full-size text bitmap.
            // shortcut: off by a pixel or so from wrapping at that size, exact if TextStep gave its strip height from the size alone.
            let f = min(1, 1024 / max(result.width, result.height))
            let small = blank(CGSize(width: max(1, (result.width * f).rounded()), height: max(1, (result.height * f).rounded())))
            let strip = TextStep.apply(small, s.text, values: values, scale: f).extent.height - small.extent.height
            result.height += (strip / f).rounded()
        }
        return result
    }

    /// The preview of `image`, a small decode of an input `originalSize` big: the output at most about
    /// `maxSide` a side whatever the settings, and the size the converter writes.
    public static func preview(_ image: CGImage, originalSize: CGSize, _ s: BatchSettings, context: PipelineContext,
                               maxSide: Double = 400) throws -> (image: CGImage, size: CGSize) {
        let full = try outputSize(for: originalSize, s, values: context.values)
        let decoded = Double(max(image.width, image.height)) / Double(max(originalSize.width, originalSize.height))
        // Scaled for the output's size too: a large output would otherwise render at full size for a thumbnail.
        let scale = min(decoded, maxSide / Double(max(full.width, full.height)))
        var input = image
        if scale < decoded {
            let f = scale / decoded
            let rect = CGRect(x: 0, y: 0, width: max(1, (Double(image.width) * f).rounded()), height: max(1, (Double(image.height) * f).rounded()))
            input = try PipelineRender.cgImage(CIImage(cgImage: image).clampedToExtent()
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: f]).cropped(to: rect))
        }
        var context = context
        context.scale = scale
        context.originalSize = originalSize
        let output = try apply(input, s, context: context)
        guard s.canvas.isOn, s.canvas.autoCropBorders else { return (output, full) }
        // shortcut: with auto-crop the size comes from the preview, off by about 1/scale pixels; exact if auto-crop ran at full size.
        return (output, CGSize(width: (Double(output.width) / scale).rounded(), height: (Double(output.height) / scale).rounded()))
    }
}

/// A transparent image of `size` at the origin, for the steps' sizes alone (nothing renders it).
private func blank(_ size: CGSize) -> CIImage {
    CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
}
