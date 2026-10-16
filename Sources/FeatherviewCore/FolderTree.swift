import Foundation

/// Folders around the current one, for the folder chooser. Like `FolderScanner`, it never opens a file.
public enum FolderTree {
    /// Subfolders of `folder` in Finder order. Symlinked folders are followed; packages (`.app`,
    /// `.photoslibrary`) are skipped, as Finder shows them as files. Unreadable folders have none.
    public static func subfolders(of folder: URL, includeHidden: Bool = false) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        // Foundation won't list through a symlink, hence the resolved path; results are rebased onto
        // `folder` so they keep the path the user came by and `parent(of:)` leads back the same way.
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: keys,
            options: includeHidden ? [] : [.skipsHiddenFiles])
        else { return [] }
        return items
            .filter { item in
                // Keys come from the listing; only a symlink needs resolving to see the folder behind it.
                guard var values = try? item.resourceValues(forKeys: Set(keys)) else { return false }
                if values.isSymbolicLink == true {
                    guard let target = try? item.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys))
                    else { return false }
                    values = target
                }
                return values.isDirectory == true && values.isPackage != true
            }
            .map { folder.appendingPathComponent($0.lastPathComponent, isDirectory: true) }
            .sorted { a, b in
                // Ties ("Photos"/"photos" on a case-sensitive volume) fall back to a plain compare to stay stable.
                let order = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
                return order == .orderedSame ? a.lastPathComponent < b.lastPathComponent : order == .orderedAscending
            }
    }

    /// Images directly inside `folder` (by extension, as the viewer would list them); 0 if unreadable.
    public static func imageCount(in folder: URL, includeHidden: Bool = false) -> Int {
        // FolderScanner treats a non-folder as a file and would count its parent's images.
        guard (try? folder.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return 0 }
        return (try? FolderScanner.images(around: folder, includeHidden: includeHidden).count) ?? 0
    }

    /// The folder `folder` sits in, by its own path (not a symlink's target), or nil at the root.
    public static func parent(of folder: URL) -> URL? {
        let folder = folder.standardizedFileURL
        let parent = folder.deletingLastPathComponent().standardizedFileURL
        return parent.path == folder.path ? nil : parent
    }
}
