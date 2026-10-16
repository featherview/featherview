import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    /// Every type ImageIO can decode on this Mac (JPEG, PNG, HEIC, WebP, camera RAW, ...).
    static let decodable: [UTType] =
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }

    /// Decided by file extension only, so scanning a 10k-file folder never opens a file.
    public static func isDecodable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension),
              !type.conforms(to: .pdf) else { return false }
        return decodable.contains { type.conforms(to: $0) }
    }
}
