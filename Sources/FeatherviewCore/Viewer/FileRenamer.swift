import Foundation

/// Why a new name is refused. `.empty` has no message: callers treat it as a cancel.
public enum RenameProblem: Error, Equatable {
    case empty, invalidCharacter, hidden, tooLong, taken(String)

    public var message: String? {
        switch self {
        case .empty: nil
        case .invalidCharacter: String(localized: "A name can't contain “/” or “:”.")
        case .hidden: String(localized: "A name can't start with “.”: the file would be hidden.")
        case .tooLong: String(localized: "That name is too long.")
        case .taken(let name): String(localized: "“\(name)” is already taken. Choose a different name.")
        }
    }
}

/// Renames a file in its folder, sidecars along, and never overwrites anything.
public enum FileRenamer {
    public static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func check(_ name: String) -> RenameProblem? {
        let name = trimmed(name)
        if name.isEmpty { return .empty }
        if name.contains("/") || name.contains(":")
            || name.unicodeScalars.contains { $0.properties.generalCategory == .control } { return .invalidCharacter }
        if name.hasPrefix(".") { return .hidden }
        // APFS and HFS+ cap a name at 255 characters (UTF-16 units on HFS+), not UTF-8 bytes.
        if name.utf16.count > 255 { return .tooLong }
        return nil
    }

    /// The part before the last "." (UTF-16, for a text field's selection); the whole name without one.
    public static func stemRange(of name: String) -> NSRange {
        let ns = name as NSString
        let dot = ns.range(of: ".", options: .backwards).location
        return NSRange(location: 0, length: dot == NSNotFound || dot == 0 ? ns.length : dot)
    }

    public static func extensionChange(from file: URL, to name: String) -> (old: String, new: String)? {
        let old = file.pathExtension, new = (trimmed(name) as NSString).pathExtension
        return old.lowercased() == new.lowercased() ? nil : (old, new)
    }

    /// Renames `file` to `name` in its folder, each sidecar to the new stem with its own extension.
    /// Checks every target first: if one is another item, throws `.taken` and changes nothing.
    @discardableResult
    public static func rename(_ file: URL, to name: String, sidecars: [URL]) throws -> URL {
        if let problem = check(name) { throw problem }
        let name = trimmed(name)
        if name == file.lastPathComponent { return file }
        // Target paths stay strings: URL decomposes "é" into two characters, which can push a name past 255.
        let folder = file.deletingLastPathComponent().path
        let stem = (name as NSString).deletingPathExtension
        let moves = [(file.path, "\(folder)/\(name)")] + sidecars.map { sidecar in
            let ext = sidecar.pathExtension
            return (sidecar.path, "\(folder)/\(ext.isEmpty ? stem : "\(stem).\(ext)")")
        }
        for (source, target) in moves where isAnotherItem(target, than: source) {
            throw RenameProblem.taken((target as NSString).lastPathComponent)
        }
        try move(moves[0].0, to: moves[0].1)
        for (sidecar, target) in moves.dropFirst() {
            // shortcut: a sidecar that fails to rename stays behind silently; surface it if users report lost edits.
            try? move(sidecar, to: target)
        }
        return URL(filePath: moves[0].1)
    }

    /// RENAME_EXCL: an existing target fails atomically (no check-then-rename race). A case-only change
    /// on a case-insensitive volume is the same item, which the volume allows. Renames a link, not its target.
    private static func move(_ source: String, to target: String) throws {
        if source == target { return }
        guard renamex_np(source, target, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { throw RenameProblem.taken((target as NSString).lastPathComponent) }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Whether `target` exists and isn't `source` itself (the same file under another case).
    /// Neither path is resolved: a link is its own item, and a dangling one still takes its name.
    private static func isAnotherItem(_ target: String, than source: String) -> Bool {
        guard (try? FileManager.default.attributesOfItem(atPath: target)) != nil else { return false }
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? URL(filePath: source).resourceValues(forKeys: key).fileResourceIdentifier,
              let y = try? URL(filePath: target).resourceValues(forKeys: key).fileResourceIdentifier
        else { return true }
        return !x.isEqual(y)
    }
}
