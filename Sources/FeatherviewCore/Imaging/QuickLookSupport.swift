import CoreGraphics
import Foundation

/// What the Finder thumbnail and Quick Look preview extensions need (spec "Formats", Finder previews):
/// the types only Featherview reads, and decodes through the viewer's own code.
public enum QuickLookSupport {
    /// The types of every own format except PDF and SVG, which macOS previews itself.
    public static let contentTypes = [
        "net.mynetx.featherview.qoi", "net.mynetx.featherview.pcx", "net.mynetx.featherview.dcx",
        "public.xbitmap-image", "net.mynetx.featherview.xpm", "net.mynetx.featherview.wbmp",
        "net.mynetx.featherview.sun-raster", "net.mynetx.featherview.ilbm", "net.mynetx.featherview.xcf",
        "net.mynetx.featherview.psp", "net.mynetx.featherview.pdn",
    ]

    /// `image` scaled to fit `maximum`, never enlarged.
    public static func thumbnailSize(image: CGSize, maximum: CGSize) -> CGSize {
        let scale = min(1, maximum.width / image.width, maximum.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Page 1 decoded for a thumbnail of at most `maximum` points at `scale`, and the size to show it at.
    public static func thumbnail(_ url: URL, maximum: CGSize, scale: CGFloat) throws -> (image: CGImage, size: CGSize) {
        let side = Int((max(maximum.width, maximum.height) * scale).rounded(.up))
        let image = try ImageDecoder.decode(url, maxPixelSize: side)
        return (image, thumbnailSize(image: CGSize(width: image.width, height: image.height), maximum: maximum))
    }

    /// The screen a preview fits when the extension sees none: a common Retina size, so a huge image
    /// never decodes at full size.
    public static let fallbackScreen = PixelSize(width: 3024, height: 1964)

    /// Page 1 decoded to fit the screens, as the viewer shows it.
    public static func preview(_ url: URL, screens: [PixelSize]) throws -> CGImage {
        try ImageDecoder.decode(url, fitting: screens.isEmpty ? [fallbackScreen] : screens)
    }
}
