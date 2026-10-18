import Foundation

/// The batch window's images column: files and folders the user added, in the order they'll run.
public struct BatchInputList: Equatable, Sendable {
    public private(set) var items: [BatchInput] = []
    /// `pathKey` of every item, kept so an add resolves only the incoming paths (it hits the disk).
    private var keys: Set<String> = []
    /// Each row's key as stored at add: recomputing it on remove can differ once a symlink or volume changed.
    private var keyOf: [URL: String] = [:]
    /// Each row's file size, read at add (off the main thread), so the total never re-reads the list.
    private var sizeOf: [URL: Int] = [:]
    /// Sum of the items' file sizes as read at add.
    public private(set) var totalBytes = 0

    public init(_ items: [BatchInput] = []) {
        append(items)
    }

    /// Appends in Finder order; skips files already in the list (same resolved path) and
    /// anything that isn't a decodable image.
    public mutating func add(files: [URL]) {
        append(FolderScanner.inFinderOrder(files.filter(Self.isImageFile)).map { BatchInput(url: $0) })
    }

    /// A decodable image that is a file (through symlinks), not a folder or package named like one.
    private static func isImageFile(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return ImageFormats.isDecodable(url)
            && FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && !isFolder.boolValue
    }

    /// Lists `folder` (and, with `subfolders`, every folder below it, skipping hidden ones and
    /// packages) off the caller's thread: call it from a background task. Hidden and non-image
    /// files are skipped. Each folder's files in Finder order, folders depth-first in Finder
    /// order. Every item gets `root: folder` and a URL below `folder`'s path as given.
    public static func scan(folder: URL, subfolders: Bool) throws -> [BatchInput] {
        var inputs: [BatchInput] = []
        try scan(folder, root: folder, subfolders: subfolders, into: &inputs)
        return inputs
    }

    /// Dropped files and folders in the order given; a folder (also through a symlink) adds with
    /// its subfolders. Off the caller's thread, like `scan(folder:subfolders:)`. `unreadable` names
    /// the folders that couldn't be listed.
    public static func scan(dropped urls: [URL]) -> (list: BatchInputList, unreadable: [URL]) {
        var list = BatchInputList()
        var files: [URL] = []
        var unreadable: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                files.append(url)
                continue
            }
            // A package (app bundle, Photos library) is one item in Finder, not a folder of inputs.
            if (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isPackageKey]).isPackage) == true { continue }
            list.add(files: files)
            files = []
            do { list.append(try scan(folder: url, subfolders: true)) } catch { unreadable.append(url) }
        }
        list.add(files: files)
        return (list, unreadable)
    }

    private static func scan(_ folder: URL, root: URL, subfolders: Bool, into inputs: inout [BatchInput]) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isRegularFileKey, .isSymbolicLinkKey]
        // Resource values come from the directory listing: no file is opened.
        // Listing fails on a symlinked folder the user chose, so list its target; entries found
        // below are not followed.
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var files: [URL] = []
        var folders: [URL] = []
        for listed in entries {
            // Named under `folder` as given, so `root` stays a prefix ("Recreate subfolders" needs it).
            let entry = folder.appendingPathComponent(listed.lastPathComponent)
            guard let values = try? listed.resourceValues(forKeys: Set(keys)) else { continue }
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
        for input in inputs {
            let key = pathKey(input.url)
            guard keys.insert(key).inserted else { continue }
            keyOf[input.url] = key
            add(size: input.fileSize(), of: input)
        }
    }

    private mutating func add(size: Int, of input: BatchInput) {
        sizeOf[input.url] = size
        totalBytes += size
        items.append(input)
    }

    /// Appends `other`'s items with the keys it resolved at add, so a list built off the main
    /// thread merges without touching the disk.
    public mutating func append(_ other: BatchInputList) {
        for input in other.items {
            guard let key = other.keyOf[input.url], keys.insert(key).inserted else { continue }
            keyOf[input.url] = key
            add(size: other.sizeOf[input.url] ?? 0, of: input)
        }
    }

    public mutating func remove(at offsets: IndexSet) {
        for index in offsets.reversed() where items.indices.contains(index) {
            let url = items.remove(at: index).url
            if let key = keyOf.removeValue(forKey: url) { keys.remove(key) }
            totalBytes -= sizeOf.removeValue(forKey: url) ?? 0
        }
    }

    public mutating func removeAll() {
        items.removeAll()
        keys.removeAll()
        keyOf.removeAll()
        sizeOf.removeAll()
        totalBytes = 0
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
        append(urls.filter(Self.isImageFile).map { BatchInput(url: $0) })  // the saved order is kept
        return (items.count - before, missing)
    }
}
