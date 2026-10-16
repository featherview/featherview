import Foundation

public enum FolderScanner {
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    public static func images(around url: URL) throws -> [URL] {
        let resolved = url.resolvingSymlinksInPath()
        let isFolder = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? resolved : url.deletingLastPathComponent()
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles])
        // shortcut: localizedStandardCompare sorts 10,000 names in ~220 ms (release), half the
        // folder-open budget; show the opened file first and sort later if that budget slips.
        return items
            .filter { ImageFormats.isDecodable($0) && isRegularFile($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Keys come from the directory listing; only symlinks cost an extra lookup.
    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        if values.isSymbolicLink == true {
            return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        return values.isRegularFile == true
    }
}
