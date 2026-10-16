import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    /// Every type ImageIO can decode on this Mac (JPEG, PNG, HEIC, WebP, camera RAW, ...).
    static let decodable: [UTType] =
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }

    /// Decided by file extension only, so scanning a 10k-file folder never opens a file.
    public static func isDecodable(_ url: URL) -> Bool {
        if OwnDecoders.format(for: url) != nil { return true }
        // macOS has no UTType for these JPEG extensions (browsers save .jfif), ImageIO reads them.
        var ext = ["jfif", "jif", "jfi"].contains(url.pathExtension.lowercased()) ? "jpg" : url.pathExtension
        // macOS has no UTType for Photoshop Large Documents, ImageIO reads them as PSD (by content).
        if ext.lowercased() == "psb" { ext = "psd" }
        // PDF is read by our own decoder above; ImageIO would give only its first page, without pages.
        guard let type = UTType(filenameExtension: ext), !type.conforms(to: .pdf) else { return false }
        return decodable.contains { type.conforms(to: $0) }
    }

    /// Only a TIFF or a multi-page own format (DCX) can have pages (`ImageDecoder.pageCount`); by
    /// extension, so other files skip that header read.
    // shortcut: a TIFF saved under another extension shows its first page only, read the type from the decode if that comes up.
    public static func mayHavePages(_ url: URL) -> Bool {
        if let own = OwnDecoders.format(for: url) { return own.hasPages }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .tiff) == true
    }
}
