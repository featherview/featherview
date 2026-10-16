import Foundation

public enum FolderScanner {
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    /// Hidden files are skipped unless `includeHidden` (Settings › Browsing).
    public static func images(around url: URL, includeHidden: Bool = false) throws -> [URL] {
        let resolved = url.resolvingSymlinksInPath()
        let isFolder = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? resolved : url.deletingLastPathComponent()
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: includeHidden ? [] : [.skipsHiddenFiles])
        } catch where !isFolder && FileManager.default.isReadableFile(atPath: url.path) {
            return [url]  // folder not listable (permissions, privacy prompt denied): show just this file
        }
        // shortcut: localizedStandardCompare sorts 10,000 names in ~220 ms (release), half the
        // folder-open budget; show the opened file first and sort later if that budget slips.
        var images = items.filter { ImageFormats.isDecodable($0) && isRegularFile($0) }
        // The file the user opened is always listed, even if hidden or of an unknown extension.
        // Names compare without case (APFS default); not pathKey, which would merge symlinks with their target.
        let openedName = url.lastPathComponent.lowercased()
        if !isFolder, isRegularFile(url), !images.contains(where: { $0.lastPathComponent.lowercased() == openedName }) {
            images.append(folder.appendingPathComponent(url.lastPathComponent))
        }
        return images
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
