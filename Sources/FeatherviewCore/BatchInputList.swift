import Foundation

/// The batch window's images column: files and folders the user added, in the order they'll run.
public struct BatchInputList: Equatable, Sendable {
    public private(set) var items: [BatchInput]

    public init(_ items: [BatchInput] = []) {
        self.items = items
    }

    /// Appends in Finder order; skips files already in the list (same resolved path) and
    /// anything that isn't a decodable image.
    public mutating func add(files: [URL]) {
        append(FolderScanner.inFinderOrder(files.filter(ImageFormats.isDecodable)).map { BatchInput(url: $0) })
    }

    /// Lists `folder` (and, with `subfolders`, every folder below it, skipping hidden ones and
    /// packages) off the caller's thread: call it from a background task. Hidden and non-image
    /// files are skipped. Each folder's files in Finder order, folders depth-first in Finder
    /// order. Every item gets `root: folder`.
    public static func scan(folder: URL, subfolders: Bool) throws -> [BatchInput] {
        var inputs: [BatchInput] = []
        // Listing fails on a symlinked folder the user chose; only subfolders found below stay unfollowed.
        try scan(folder.resolvingSymlinksInPath(), root: folder, subfolders: subfolders, into: &inputs)
        return inputs
    }

    private static func scan(_ folder: URL, root: URL, subfolders: Bool, into inputs: inout [BatchInput]) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isRegularFileKey, .isSymbolicLinkKey]
        // Resource values come from the directory listing: no file is opened.
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var files: [URL] = []
        var folders: [URL] = []
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            // Symlinks report the link itself, so a symlinked folder is never entered (no loops).
            if values.isDirectory == true {
                if values.isPackage != true { folders.append(entry) }
            } else if ImageFormats.isDecodable(entry) {
                let isFile = values.isSymbolicLink == true
                    ? (try? entry.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    : values.isRegularFile == true
                if isFile { files.append(entry) }
            }
        }
        inputs += FolderScanner.inFinderOrder(files).map { BatchInput(url: $0, root: root) }
        guard subfolders else { return }
        for sub in FolderScanner.inFinderOrder(folders) {
            try? scan(sub, root: root, subfolders: true, into: &inputs)  // an unreadable subfolder is skipped
        }
    }

    /// Same de-duplication as `add(files:)`.
    public mutating func append(_ inputs: [BatchInput]) {
        var seen = Set(items.map { pathKey($0.url) })
        for input in inputs where seen.insert(pathKey(input.url)).inserted {
            items.append(input)
        }
    }

    public mutating func remove(at offsets: IndexSet) {
        for index in offsets.reversed() where items.indices.contains(index) { items.remove(at: index) }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Finder order of the file names, stable.
    public mutating func sortByName() {
        let names = items.map(\.url.lastPathComponent)
        items = items.indices.sorted {
            switch names[$0].localizedStandardCompare(names[$1]) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0 < $1
            }
        }.map { items[$0] }
    }

    /// Moves the rows at `offsets` by `delta` (up = −1, down = +1); rows keep their relative order
    /// and stop at either end.
    public mutating func move(_ offsets: IndexSet, by delta: Int) {
        var selected = Set(offsets.filter(items.indices.contains))
        let step = delta < 0 ? -1 : 1
        for _ in 0..<abs(delta) {
            // Rows nearest the destination go first, so a row blocked by a selected neighbour stays.
            for index in step < 0 ? selected.sorted() : selected.sorted(by: >) {
                let target = index + step
                guard items.indices.contains(target), !selected.contains(target) else { continue }
                items.swapAt(index, target)
                selected.remove(index)
                selected.insert(target)
            }
        }
    }

    /// One absolute path per line, UTF-8, "\n" line ends.
    public func listText() -> String {
        items.map { $0.url.path + "\n" }.joined()
    }

    /// Paths from a saved list (blank lines, "#" comments and missing files skipped); returns how
    /// many lines named files that no longer exist.
    public mutating func load(listText: String) -> (added: Int, missing: Int) {
        var urls: [URL] = []
        var missing = 0
        for line in listText.split(whereSeparator: \.isNewline) {
            let path = line.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !path.hasPrefix("#") else { continue }
            if FileManager.default.fileExists(atPath: path) {
                urls.append(URL(fileURLWithPath: path))
            } else {
                missing += 1
            }
        }
        let before = items.count
        append(urls.filter(ImageFormats.isDecodable).map { BatchInput(url: $0) })  // the saved order is kept
        return (items.count - before, missing)
    }
}
