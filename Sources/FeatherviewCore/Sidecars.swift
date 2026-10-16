import Foundation

/// Files that belong to an image and travel with it: `IMG_1.xmp`, `IMG_1.AAE`, `IMG_1.thm` for `IMG_1.JPG`.
public enum Sidecars {
    public static let extensions: Set<String> = ["xmp", "aae", "thm"]

    /// Sidecars next to `image`: same base name (any case), a sidecar extension (any case).
    /// Lists the folder once, so names keep their real case on case-insensitive volumes.
    public static func files(for image: URL) -> [URL] {
        let stem = image.deletingPathExtension().lastPathComponent.lowercased()
        let folder = image.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { item in
            item.deletingPathExtension().lastPathComponent.lowercased() == stem
                && extensions.contains(item.pathExtension.lowercased())
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
