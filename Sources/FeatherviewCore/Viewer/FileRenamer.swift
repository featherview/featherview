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
            || name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) { return .invalidCharacter }
        if name.hasPrefix(".") { return .hidden }
        if name.utf8.count > 255 { return .tooLong }
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
        let folder = file.deletingLastPathComponent()
        let stem = (name as NSString).deletingPathExtension
        let moves = [(file, folder.appendingPathComponent(name))] + sidecars.map { sidecar in
            let ext = sidecar.pathExtension
            return (sidecar, folder.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)"))
        }
        for (source, target) in moves where isAnotherItem(target, than: source) {
            throw RenameProblem.taken(target.lastPathComponent)
        }
        try move(file, to: moves[0].1)
        for (sidecar, target) in moves.dropFirst() {
            // shortcut: a sidecar that fails to rename stays behind silently; surface it if users report lost edits.
            try? move(sidecar, to: target)
        }
        return moves[0].1
    }

    /// RENAME_EXCL: an existing target fails atomically (no check-then-rename race). A case-only change
    /// on a case-insensitive volume is the same item, which the volume allows. Renames a link, not its target.
    private static func move(_ source: URL, to target: URL) throws {
        if source.lastPathComponent == target.lastPathComponent { return }
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { throw RenameProblem.taken(target.lastPathComponent) }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Whether `target` exists and isn't `source` itself (the same file under another case).
    /// Neither path is resolved: a link is its own item, and a dangling one still takes its name.
    private static func isAnotherItem(_ target: URL, than source: URL) -> Bool {
        guard (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil else { return false }
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? URL(filePath: source.path).resourceValues(forKeys: key).fileResourceIdentifier,
              let y = try? URL(filePath: target.path).resourceValues(forKeys: key).fileResourceIdentifier
        else { return true }
        return !x.isEqual(y)
    }
}
