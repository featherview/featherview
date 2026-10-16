import Foundation

/// Folders around the current one, for the folder chooser. Like `FolderScanner`, it never opens a file.
public enum FolderTree {
    /// Subfolders of `folder` in Finder order. Symlinked folders are followed; packages (`.app`,
    /// `.photoslibrary`) are skipped, as Finder shows them as files. Unreadable folders have none.
    public static func subfolders(of folder: URL, includeHidden: Bool = false) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: keys,
            options: includeHidden ? [] : [.skipsHiddenFiles])
        else { return [] }
        return items
            .filter { item in
                // resourceValues on a symlink describes the link; resolve it to see a folder behind it.
                let values = try? item.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys))
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Images directly inside `folder` (by extension, as the viewer would list them); 0 if unreadable.
    public static func imageCount(in folder: URL, includeHidden: Bool = false) -> Int {
        // FolderScanner treats a non-folder as a file and would count its parent's images.
        guard (try? folder.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return 0 }
        return (try? FolderScanner.images(around: folder, includeHidden: includeHidden).count) ?? 0
    }

    /// The parent folder, or nil at the root of the file system.
    public static func parent(of folder: URL) -> URL? {
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        let parent = resolved.deletingLastPathComponent().standardizedFileURL
        return parent.path == resolved.path ? nil : parent
    }
}
