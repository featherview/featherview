import CoreGraphics
import Foundation

/// What the Finder thumbnail and Quick Look preview extensions need (spec "Formats", Finder previews):
/// the types only Featherview reads, and decodes through the viewer's own code.
public enum QuickLookSupport {
    /// The types of every own format except PDF and SVG, which macOS previews itself, and PAM, which ImageIO
    /// reads but macOS has no type for, so its own previews never get it.
    public static let contentTypes = [
        "net.mynetx.featherview.qoi", "net.mynetx.featherview.pcx", "net.mynetx.featherview.dcx",
        "public.xbitmap-image", "net.mynetx.featherview.xpm", "net.mynetx.featherview.wbmp",
        "net.mynetx.featherview.sun-raster", "net.mynetx.featherview.ilbm", "net.mynetx.featherview.xcf",
        "net.mynetx.featherview.psp", "net.mynetx.featherview.pdn", "net.mynetx.featherview.pam",
        "net.mynetx.featherview.farbfeld", "net.mynetx.featherview.macpaint", "net.mynetx.featherview.xwd",
        "net.mynetx.featherview.fits", "net.mynetx.featherview.ani", "net.mynetx.featherview.openraster",
        "net.mynetx.featherview.krita", "net.mynetx.featherview.procreate", "com.apple.macpaint-image",
        "net.mynetx.featherview.photo-cd", "net.mynetx.featherview.jpeg-xr", "net.mynetx.featherview.bpg",
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

    /// Page 1 decoded to fit the screens, as the viewer shows it.
    public static func preview(_ url: URL, screens: [PixelSize]) throws -> CGImage {
        try ImageDecoder.decode(url, fitting: screens.isEmpty ? [PixelSize.fallbackScreen] : screens)
    }
}
