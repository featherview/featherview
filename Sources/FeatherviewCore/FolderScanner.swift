import Foundation

public enum FolderScanner {
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    public static func images(around url: URL) throws -> [URL] {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? url : url.deletingLastPathComponent()
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return items
            .filter(ImageFormats.isDecodable)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
