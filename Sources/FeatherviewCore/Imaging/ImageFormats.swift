import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    /// Every type ImageIO can decode on this Mac (JPEG, PNG, HEIC, WebP, camera RAW, ...).
    static let decodable: [UTType] =
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }

    /// Other spellings of a format's extension: macOS has no UTType ImageIO lists for .jfif, .jif, .jfi (browsers
    /// save .jfif) or .apng, and HEIF's extensions name the format the writers call HEIC.
    private static let aliases = ["jfif": "jpg", "jif": "jpg", "jfi": "jpg", "heif": "heic", "hif": "heic", "apng": "png"]

    /// The extension of the format `ext` names, lowercased (`jfif` is `jpg`).
    public static func canonicalExtension(_ ext: String) -> String {
        let ext = ext.lowercased()
        return aliases[ext] ?? ext
    }

    /// Decided by file extension only, so scanning a 10k-file folder never opens a file.
    public static func isDecodable(_ url: URL) -> Bool {
        if OwnDecoders.format(for: url) != nil { return true }
        var ext = canonicalExtension(url.pathExtension)
        // Not that format, but ImageIO reads them by content with it: Photoshop Large Documents as PSD, Netpbm's
        // PAM with the rest of the family (macOS has no UTType for either).
        ext = ["psb": "psd", "pam": "pbm"][ext] ?? ext
        // PDF is read by our own decoder above; ImageIO would give only its first page, without pages.
        guard let type = UTType(filenameExtension: ext), !type.conforms(to: .pdf) else { return false }
        return decodable.contains { type.conforms(to: $0) }
    }

    /// What macOS's desktop picture can show: ImageIO's formats only, not our own decoders or PDF.
    public static func desktopCanShow(_ url: URL) -> Bool {
        isDecodable(url) && OwnDecoders.format(for: url) == nil && UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) != true
    }

    /// Only a TIFF or a multi-page own format (DCX) can have pages (`ImageDecoder.pageCount`); by
    /// extension, so other files skip that header read.
    // shortcut: a TIFF saved under another extension shows its first page only, read the type from the decode if that comes up.
    public static func mayHavePages(_ url: URL) -> Bool {
        if let own = OwnDecoders.format(for: url) { return own.hasPages }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .tiff) == true
    }

    /// Only these can be animations (`Animation.read`); by extension, so stills skip that property read.
    public static func mayAnimate(_ url: URL) -> Bool {
        if let own = OwnDecoders.format(for: url) { return own.delays != nil }
        return ["gif", "png", "apng", "webp", "heic", "heics", "heif", "avif"].contains(url.pathExtension.lowercased())
    }
}
