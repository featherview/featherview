import CoreGraphics
import CoreImage
import Foundation

/// What a pipeline run needs besides the settings.
public struct PipelineContext: Sendable {
    public var values: TextValues
    /// Multiplies pixel-valued settings: 1 for output, < 1 for the preview's small decode.
    public var scale: Double = 1
    /// The upright size before a smaller decode (`ResizeStep.decodeLimit`), so the resize keeps the exact target.
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
        picture = ResizeStep.apply(picture, s.resize, scale: scale, originalSize: context.originalSize)
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
}
