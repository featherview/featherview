import AppKit
import FeatherviewCore

/// SVG through AppKit (spec "Formats"); here, not in FeatherviewCore, because it needs NSImage.
enum SVGFormat {
    static let format = OwnFormat(
        name: "SVG", extensions: ["svg"],
        size: { data, _ in NSImage(data: data).map { CGSize(width: $0.size.width * 2, height: $0.size.height * 2) } },
        decode: { data, _, maxPixelSize in
            guard let image = NSImage(data: data), image.size.width >= 1, image.size.height >= 1 else {
                throw OwnDecodeError.corrupt
            }
            var scale = 2.0
            if let maxPixelSize { scale = min(scale, Double(maxPixelSize) / max(image.size.width, image.size.height)) }
            let width = max(1, Int((image.size.width * scale).rounded()))
            let height = max(1, Int((image.size.height * scale).rounded()))
            guard width <= 16384, height <= 16384,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw OwnDecodeError.corrupt }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            guard let rendered = context.makeImage() else { throw OwnDecodeError.corrupt }
            return rendered
        })
}
