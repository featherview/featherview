import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    /// Every type ImageIO can decode on this Mac (JPEG, PNG, HEIC, WebP, camera RAW, ...).
    static let decodable: [UTType] =
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }

    /// Decided by file extension only, so scanning a 10k-file folder never opens a file.
    public static func isDecodable(_ url: URL) -> Bool {
        // macOS has no UTType for these JPEG extensions (browsers save .jfif), ImageIO reads them.
        let ext = ["jfif", "jif", "jfi"].contains(url.pathExtension.lowercased()) ? "jpg" : url.pathExtension
        guard let type = UTType(filenameExtension: ext),
              !type.conforms(to: .pdf) else { return false }
        return decodable.contains { type.conforms(to: $0) }
    }
}
