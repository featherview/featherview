import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ⌘C's pasteboard data, encoded off the main thread.
public enum ClipboardImage {
    /// PNG, not NSImage's uncompressed TIFF: the pasteboard refuses data above ~256 MB (≈64 MP RGBA as TIFF).
    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
