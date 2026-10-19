import Foundation

public enum FolderScanner {
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    /// Hidden files are skipped unless `includeHidden` (Settings › Browsing). Without `sorted`, in
    /// listing order: sort with `inFinderOrder`, or find the first with `firstInFinderOrder`.
    public static func images(around url: URL, includeHidden: Bool = false, sorted: Bool = true) throws -> [URL] {
        let resolved = url.resolvingSymlinksInPath()
        let isFolder = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? resolved : url.deletingLastPathComponent()
        let entries: [(name: String, type: UInt8)]
        do {
            entries = try listing(of: folder)
        } catch where !isFolder && FileManager.default.isReadableFile(atPath: url.path) {
            return [url]  // folder not listable (permissions, privacy prompt denied): show just this file
        }
        // Asked once per extension: per file, the type lookup took 45 ms for 10,000 files.
        var decodable: [String: Bool] = [:]
        var images: [URL] = []
        for entry in entries where includeHidden || !entry.name.hasPrefix(".") {
            let item = folder.appendingPathComponent(entry.name, isDirectory: false)
            let ext = item.pathExtension.lowercased()
            if decodable[ext] == nil { decodable[ext] = ImageFormats.isDecodable(item) }
            guard decodable[ext]! else { continue }
            // Symlinks, and file systems that don't report types, are looked up.
            if entry.type == UInt8(DT_REG) || [UInt8(DT_LNK), UInt8(DT_UNKNOWN)].contains(entry.type) && isRegularFile(item) {
                images.append(item)
            }
        }
        // The file the user opened is always listed, even if hidden or of an unknown extension.
        // Names compare without case (APFS default); not pathKey, which would merge symlinks with their target.
        let openedName = url.lastPathComponent.lowercased()
        if !isFolder, isRegularFile(url), !images.contains(where: { $0.lastPathComponent.lowercased() == openedName }) {
            images.append(folder.appendingPathComponent(url.lastPathComponent))
        }
        return sorted ? inFinderOrder(images) : images
    }

    /// Finder's name order (numbers by value). 45 ms for 10,000 names.
    public static func inFinderOrder(_ urls: [URL]) -> [URL] {
        // Names taken once: lastPathComponent inside the comparator made it 190 ms.
        urls.map { ($0.lastPathComponent, $0) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            .map(\.1)
    }

    /// The first of `inFinderOrder(urls)`, in 2.5 ms for 10,000 names.
    public static func firstInFinderOrder(_ urls: [URL]) -> URL? {
        urls.map { ($0.lastPathComponent, $0) }
            .min { $0.0.localizedStandardCompare($1.0) == .orderedAscending }?.1
    }

    /// Names and types straight from the directory: 11 ms for 10,000 files, where FileManager took
    /// 40 ms plus 18 ms to read the types.
    // shortcut: hidden means a leading dot; files hidden only by the hidden flag (chflags) are listed, read the flags (getattrlistbulk) if that comes up.
    private static func listing(of folder: URL) throws -> [(name: String, type: UInt8)] {
        guard let dir = opendir(folder.path) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { closedir(dir) }
        var entries: [(name: String, type: UInt8)] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) {
                String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { entries.append((name, entry.pointee.d_type)) }
        }
        return entries
    }

    /// For symlinks (followed) and entries of unknown type.
    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        if values.isSymbolicLink == true {
            return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        return values.isRegularFile == true
    }
}
