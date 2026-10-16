import AppKit
import FeatherviewCore

/// SVG through AppKit (spec "Formats"); here, not in FeatherviewCore, because it needs NSImage.
enum SVGFormat {
    static let format = OwnFormat(
        name: "SVG", extensions: ["svg"],
        size: { data, _ in NSImage(data: data).map { let s = vectorPixelSize($0.size, maxPixelSize: nil)
                                                     return CGSize(width: s.width, height: s.height) } },
        decode: { data, _, maxPixelSize in
            guard let image = NSImage(data: data), image.size.width >= 1, image.size.height >= 1 else {
                throw OwnDecodeError.corrupt
            }
            let (width, height, _) = vectorPixelSize(image.size, maxPixelSize: maxPixelSize)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
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
