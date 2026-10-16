import Foundation

/// Files that belong to an image and travel with it: `IMG_1.xmp`, `IMG_1.AAE`, `IMG_1.thm` for `IMG_1.JPG`.
public enum Sidecars {
    public static let extensions: Set<String> = ["xmp", "aae", "thm"]

    /// Sidecars next to `image`: same base name (any case), a sidecar extension (any case).
    /// None when another image shares the base name (RAW+JPEG): the sidecar may be the other one's,
    /// so it stays put. Lists the folder once, so names keep their real case on case-insensitive volumes.
    public static func files(for image: URL) -> [URL] {
        let stem = image.deletingPathExtension().lastPathComponent.lowercased()
        let name = image.lastPathComponent.lowercased()
        let folder = image.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let sameStem = items.filter { $0.deletingPathExtension().lastPathComponent.lowercased() == stem }
        let otherImage = sameStem.contains { $0.lastPathComponent.lowercased() != name && ImageFormats.isDecodable($0) }
        if otherImage { return [] }
        return sameStem.filter(isSidecar).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isSidecar(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
