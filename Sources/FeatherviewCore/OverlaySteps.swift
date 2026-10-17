import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// What `{name}` `{folder}` `{date}` `{n}` become in the batch text overlay.
public struct TextValues: Sendable, Equatable {
    public var name, folder, date: String
    public var index: Int

    public init(name: String, folder: String, date: String, index: Int) {
        self.name = name; self.folder = folder; self.date = date; self.index = index
    }
}

/// The batch "Add text" step: Core Text draws the block, Core Image composites it.
public enum TextStep {
    public static func render(_ template: String, _ v: TextValues) -> String {
        // One pass, so a value such as a file named "{date}" is never replaced again.
        template.replacing(/\{(name|folder|date|n)(?::(\d+))?\}/) { match in
            switch match.1 {
            case "name": return match.2 == nil ? v.name : String(match.0)
            case "folder": return match.2 == nil ? v.folder : String(match.0)
            case "date": return match.2 == nil ? v.date : String(match.0)
            default:
                let digits = String(v.index)
                let width = min(match.2.flatMap { Int($0) } ?? 0, 10)  // same cap as RenamePattern
                return String(repeating: "0", count: max(0, width - digits.count)) + digits
            }
        }
    }

    /// `scale` is the preview's decode scale; every size here is a share of the image, so it scales by itself.
    public static func apply(_ image: CIImage, _ s: TextSettings, values: TextValues, scale: Double) -> CIImage {
        let string = render(s.text, values)
        let extent = image.extent
        guard !string.isEmpty, !extent.isEmpty, !extent.isInfinite else { return image }
        let shorter = min(extent.width, extent.height)
        let size = max(1, s.sizePercent.clamped(0.5, 50) / 100 * shorter)
        let margin = (s.marginPercent.clamped(0, 25) / 100 * shorter).rounded()
        guard let block = textBlock(string, s, size: size) else { return image }
        let blockSize = block.extent.size

        switch s.placement {
        case .inImage:
            let origin = place(blockSize, in: extent.size, at: s.position, margin: margin)
            return block.transformed(by: .init(translationX: origin.x, y: origin.y))
                .composited(over: image).cropped(to: extent)
        case .stripBelow, .stripAbove:
            let below = s.placement == .stripBelow
            let strip = blockSize.height + 2 * margin
            let stripRect = CGRect(x: 0, y: below ? 0 : extent.height, width: extent.width, height: strip)
            var fill = s.backgroundBox ? s.boxColour : .black
            fill.alpha = 1
            let background = CIImage(color: CIColor(cgColor: fill.cgColor)).cropped(to: stripRect)
            let x = place(blockSize, in: extent.size, at: s.position, margin: margin).x
            let text = block.transformed(by: .init(translationX: x, y: stripRect.minY + margin))
            let picture = image.transformed(by: .init(translationX: 0, y: below ? strip : 0))
            return text.composited(over: picture.composited(over: background))
                .cropped(to: CGRect(x: 0, y: 0, width: extent.width, height: extent.height + strip))
        }
    }

    /// The text (with its box and shadow) on a transparent bitmap, padded by size / 4 on every side.
    private static func textBlock(_ string: String, _ s: TextSettings, size: Double) -> CIImage? {
        let font = CTFontCreateWithName(s.fontName as CFString, size, nil)  // unknown names fall back to the system font
        var alignment: CTTextAlignment = switch s.position {
        case .topLeft, .left, .bottomLeft: .left
        case .top, .center, .bottom: .center
        case .topRight, .right, .bottomRight: .right
        }
        let paragraph = withUnsafeBytes(of: &alignment) { bytes in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: bytes.count, value: bytes.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributed = NSAttributedString(string: string, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: s.colour.cgColor,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                               CGSize(width: 100_000, height: 100_000), nil)
        let pad = (size / 4).rounded(.up)
        let textRect = CGRect(x: pad, y: pad, width: fit.width.rounded(.up), height: fit.height.rounded(.up))
        let width = Int(textRect.width + 2 * pad), height = Int(textRect.height + 2 * pad)
        guard textRect.width > 0, textRect.height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Opacity applies to the whole layer, so text over its box doesn't show the box through.
        context.setAlpha(s.opacity.clamped(0, 1))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if s.backgroundBox {
            context.setFillColor(s.boxColour.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        if s.shadow {
            context.setShadow(offset: CGSize(width: size / 20, height: -size / 20), blur: size / 15,
                              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
        }
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil), context)
        context.endTransparencyLayer()
        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}

public enum WatermarkError: Error, Equatable {
    /// The watermark file's name.
    case unreadable(String)
}

/// The batch "Watermark" step: an image file composited over each output.
public enum WatermarkStep {
    /// Loads the watermark once per batch (Task 8 caches it); throws when the file can't be read.
    public static func load(_ path: String) throws -> CIImage {
        let url = URL(fileURLWithPath: path)
        guard !path.isEmpty, let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, !image.extent.isInfinite
        else { throw WatermarkError.unreadable(path.isEmpty ? "" : url.lastPathComponent) }
        return image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    public static func apply(_ image: CIImage, watermark: CIImage, _ s: WatermarkSettings) -> CIImage {
        let extent = image.extent, mark = watermark.extent
        guard !extent.isEmpty, !extent.isInfinite, !mark.isEmpty, !mark.isInfinite else { return image }
        let factor = s.widthPercent.clamped(1, 100) / 100 * extent.width / mark.width
        let size = CGSize(width: mark.width * factor, height: mark.height * factor)
        let margin = (s.marginPercent.clamped(0, 25) / 100 * min(extent.width, extent.height)).rounded()
        let origin = place(size, in: extent.size, at: s.position, margin: margin)
        let faded = watermark
            .transformed(by: CGAffineTransform(translationX: -mark.minX, y: -mark.minY).scaledBy(x: factor, y: factor))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: s.opacity.clamped(0, 1))])
            .transformed(by: .init(translationX: origin.x, y: origin.y))
        return faded.composited(over: image).cropped(to: extent)
    }
}

/// Core Image origin (bottom-left) of a `size` box at `anchor` in a `canvas`, `margin` from the edges,
/// on whole pixels so edges stay sharp.
private func place(_ size: CGSize, in canvas: CGSize, at anchor: ImageAnchor, margin: Double) -> CGPoint {
    let x: Double = switch anchor {
    case .topLeft, .left, .bottomLeft: margin
    case .top, .center, .bottom: (canvas.width - size.width) / 2
    case .topRight, .right, .bottomRight: canvas.width - margin - size.width
    }
    let fromTop: Double = switch anchor {
    case .topLeft, .top, .topRight: margin
    case .left, .center, .right: (canvas.height - size.height) / 2
    case .bottomLeft, .bottom, .bottomRight: canvas.height - margin - size.height
    }
    return CGPoint(x: x.rounded(), y: (canvas.height - fromTop - size.height).rounded())
}

private extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { isNaN ? low : Swift.min(Swift.max(self, low), high) }
}
