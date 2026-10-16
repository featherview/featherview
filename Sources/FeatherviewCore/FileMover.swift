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
        // move/copyItem fail if the target exists, so a file created meanwhile is never overwritten.
        switch operation {
        case .move: try manager.moveItem(at: file, to: target)
        case .copy: try manager.copyItem(at: file, to: target)
        }
        for sidecar in sidecars {
            let sidecarTarget = folder.appendingPathComponent(name(stem, sidecar.pathExtension))
            // shortcut: a sidecar that fails to move stays behind silently; surface it if users report lost edits.
            switch operation {
            case .move: try? manager.moveItem(at: sidecar, to: sidecarTarget)
            case .copy: try? manager.copyItem(at: sidecar, to: sidecarTarget)
            }
        }
        return target
    }

    /// The first of "IMG_1", "IMG_1 2", "IMG_1 3", … free for the image and every sidecar.
    static func freeStem(for file: URL, sidecars: [URL], in folder: URL) -> String {
        let base = file.deletingPathExtension().lastPathComponent
        let extensions = [file.pathExtension] + sidecars.map(\.pathExtension)
        var number = 1
        while true {
            let stem = number == 1 ? base : "\(base) \(number)"
            let taken = extensions.contains { ext in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name(stem, ext)).path)
            }
            if !taken { return stem }
            number += 1
        }
    }

    /// Asks the volume, so `Pics` and `pics` are one folder only where the volume ignores case.
    static func sameItem(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
              let y = try? b.resourceValues(forKeys: key).fileResourceIdentifier else { return false }
        return x.isEqual(y)
    }

    private static func name(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}
