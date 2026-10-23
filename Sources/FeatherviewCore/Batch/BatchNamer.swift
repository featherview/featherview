import Foundation

/// Output URLs for a batch run (spec "Output"), handed out one by one as files succeed, so the
/// rename counter follows the list and skips failures.
public struct BatchNamer: Sendable {
    let settings: BatchSettings
    let fileExists: @Sendable (URL) -> Bool
    /// Inputs and names given in this run (folder key + "/" + case-folded name).
    var taken: Set<String> = []
    var folderKeys: [String: String] = [:]
    var nextSuffix: [String: Int] = [:]
    var counter = 1

    /// `inputs` are reserved (never chosen as an output, never replaced).
    public init(settings: BatchSettings, inputs: [BatchInput],
                // attributesOfItem doesn't follow symlinks, so a dangling link still counts as taken.
                fileExists: @escaping @Sendable (URL) -> Bool = { (try? FileManager.default.attributesOfItem(atPath: $0.path)) != nil }) {
        self.settings = settings
        self.fileExists = fileExists
        for input in inputs {
            taken.insert(key(input.url))
            // A symlinked input's target is also reserved, so its real file is never replaced.
            taken.insert(key(input.url.resolvingSymlinksInPath()))
        }
    }

    /// The folder `input`'s output goes to: `outputFolder` with `{folder}` = the input's parent
    /// folder name, plus the input's subfolder path below its `root` when `recreateSubfolders`.
    public func folder(for input: BatchInput) -> URL { Self.folder(for: input, settings: settings) }

    public static func folder(for input: BatchInput, settings: BatchSettings) -> URL {
        let parent = input.url.deletingLastPathComponent().standardizedFileURL
        guard !settings.outputFolder.isEmpty else { return parent }
        let name = parent.path == "/" ? "-" : parent.lastPathComponent
        // Expand ~ here: macOS 14's URL(fileURLWithPath:) doesn't, and it must match hasAbsoluteOutputFolder.
        let typed = (settings.outputFolder as NSString).expandingTildeInPath
        var folder = URL(fileURLWithPath: typed.replacingOccurrences(of: "{folder}", with: name),
                         isDirectory: true).standardizedFileURL
        if settings.safety.recreateSubfolders, let root = input.root?.standardizedFileURL {
            let rootParts = root.pathComponents, parts = parent.pathComponents
            if parts.starts(with: rootParts) {
                for part in parts.dropFirst(rootParts.count) { folder.appendPathComponent(part, isDirectory: true) }
            }
        }
        return folder
    }

    /// The next output URL for a file that succeeded. Advances the counter. Extension: the
    /// output format's, or when keeping the format the input's own, as it is.
    /// Without `replaceExisting`: never an existing file, an input, or a name given earlier in
    /// this run (case-insensitive) — " 2", " 3", … appended. With it: an existing non-input file
    /// may be returned (the caller trashes it first), never a folder; inputs and names given in this run still
    /// get suffixes.
    public mutating func next(for input: BatchInput, date: Date?) -> URL {
        names(for: input, date: date, parts: [])[0]
    }

    /// The output URLs for a file that succeeded with several outputs, one per `parts` label (one URL,
    /// as `next` gives, when `parts` is empty). Advances the counter once: every part shares `{n}`.
    /// A pattern without `{part}` gets `-{part}` appended. Each name follows `next`'s clash rules.
    public mutating func names(for input: BatchInput, date: Date?, parts: [String]) -> [URL] {
        let original = input.url.deletingPathExtension().lastPathComponent
        let pattern = RenamePattern(settings.renamePattern)
        let index = counter
        counter += 1
        let ext = settings.changeFormat ? settings.format.fileExtension : input.url.pathExtension
        let folder = folder(for: input)
        guard !parts.isEmpty else {
            return [name(pattern.baseName(original: original, index: index, date: date), ext: ext, in: folder)]
        }
        let explicit = settings.renamePattern.contains("{part}")
        return parts.map { part in
            let base = pattern.baseName(original: original, index: index, date: date, part: part)
            return name(base, label: explicit ? "" : "-" + part, ext: ext, in: folder)
        }
    }

    /// `label` (an appended part) is kept whole when the name is shortened; only `base` gives way.
    private mutating func name(_ base: String, label: String = "", ext: String, in folder: URL) -> URL {
        let suffixKey = folderKey(folder) + "/" + Self.normalized(base + label + "." + ext)
        var url = Self.fitted(base, suffix: label, ext: ext, in: folder)
        var n = nextSuffix[suffixKey] ?? 2
        while taken.contains(key(url)) || ((!settings.safety.replaceExisting || Self.isFolder(url)) && fileExists(url)) {
            url = Self.fitted(base, suffix: label + " \(n)", ext: ext, in: folder)
            n += 1
        }
        nextSuffix[suffixKey] = n
        taken.insert(key(url))
        return url
    }

    /// `base` + `suffix` + `.ext` in `folder`, the base shortened (whole characters) so the name fits
    /// APFS's 255 bytes, measured decomposed because file URLs store names that way (é is 3 bytes).
    static func fitted(_ base: String, suffix: String, ext: String, in folder: URL) -> URL {
        func bytes(_ s: some StringProtocol) -> Int { s.decomposedStringWithCanonicalMapping.utf8.count }
        let tail = suffix + (ext.isEmpty ? "" : "." + ext)
        var trimmed = Substring(base)
        // An extension too long for any base leaves an over-long name; writing it fails for that file only.
        while !trimmed.isEmpty, bytes(trimmed) > 255 - bytes(tail) { trimmed = trimmed.dropLast() }
        return folder.appendingPathComponent(trimmed + tail, isDirectory: false)
    }

    /// "Replace existing files" replaces files only, never a folder.
    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Folded like APFS compares names (ß = ss, ς = σ, ﬀ = ff), which `lowercased()` misses.
    static func normalized(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }

    /// Case-insensitive identity of `url` (its folder resolved once: pathKey hits the filesystem).
    private mutating func key(_ url: URL) -> String {
        folderKey(url.deletingLastPathComponent()) + "/" + Self.normalized(url.lastPathComponent)
    }

    private mutating func folderKey(_ folder: URL) -> String {
        if let known = folderKeys[folder.path] { return known }
        let resolved = pathKey(folder)
        folderKeys[folder.path] = resolved
        return resolved
    }
}

public enum BatchCopy {
    /// `BatchSettings.copiesUnchanged`: copies `input`'s bytes to a hidden temp file in `output`'s folder, then moves
    /// it in without replacing (`BatchConverter.moveIn`). Returns the final URL (a " 2"
    /// suffix if the name was taken meanwhile).
    public static func copy(_ input: URL, to output: URL) throws -> URL {
        let temp = ImageSaver.tempURL(in: output.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: input.resolvingSymlinksInPath(), to: temp)  // the bytes, not a link
        return try BatchConverter.moveIn(temp, to: output) { BatchConverter.moveExclusive($0, $1) }
    }
}
