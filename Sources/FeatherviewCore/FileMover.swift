import Foundation

public enum FileOperation: Sendable {
    case move, copy
}

public enum FileMover {
    /// Moves or copies `file` into `folder` (created if missing), with its `sidecars` under the same
    /// new base name. Never overwrites: if the name, or any sidecar's, is taken, " 2", " 3", … is
    /// appended. Moving into the folder the file is already in changes nothing.
    /// Returns where `file` ended up. Sidecars are best effort: one failing never undoes the image.
    @discardableResult
    public static func transfer(_ file: URL, to folder: URL, operation: FileOperation,
                                sidecars: [URL] = []) throws -> URL {
        let manager = FileManager.default
        if operation == .move, sameItem(folder, file.deletingLastPathComponent()) { return file }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = freeStem(for: file, sidecars: sidecars, in: folder)
        let target = folder.appendingPathComponent(name(stem, file.pathExtension))
        try place(file, at: target, operation)
        for sidecar in sidecars {
            // shortcut: a sidecar that fails to move stays behind silently; surface it if users report lost edits.
            try? place(sidecar, at: folder.appendingPathComponent(name(stem, sidecar.pathExtension)), operation)
        }
        return target
    }

    /// move/copyItem fail if the target exists, so a file created meanwhile is never overwritten.
    /// A symlink arrives as the file it points to: a moved or copied link could point at nothing there.
    /// Moving one removes only the link; the linked-to file stays where it is.
    private static func place(_ source: URL, at target: URL, _ operation: FileOperation) throws {
        let manager = FileManager.default
        let isLink = (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        if operation == .move, !isLink { return try manager.moveItem(at: source, to: target) }
        try manager.copyItem(at: isLink ? source.resolvingSymlinksInPath() : source, to: target)
        guard operation == .move else { return }
        do { try manager.removeItem(at: source) } catch {
            try? manager.removeItem(at: target)  // a failed move leaves no duplicate behind
            throw error
        }
    }

    /// The first of "IMG_1", "IMG_1 2", "IMG_1 3", … free for the image and every sidecar.
    static func freeStem(for file: URL, sidecars: [URL], in folder: URL) -> String {
        let base = file.deletingPathExtension().lastPathComponent
        let extensions = [file.pathExtension] + sidecars.map(\.pathExtension)
        var number = 1
        while true {
            let stem = number == 1 ? base : "\(base) \(number)"
            let taken = extensions.contains { ext in
                // attributesOfItem doesn't follow symlinks, so a dangling link still counts as taken.
                (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name(stem, ext)).path)) != nil
            }
            if !taken { return stem }
            number += 1
        }
    }

    /// Asks the volume, so `Pics` and `pics` are one folder only where the volume ignores case.
    /// Links are resolved first: resource values describe a link itself, not the folder it points to.
    static func sameItem(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? a.resolvingSymlinksInPath().resourceValues(forKeys: key).fileResourceIdentifier,
              let y = try? b.resolvingSymlinksInPath().resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return x.isEqual(y)
    }

    private static func name(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}
