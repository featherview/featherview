import Foundation
import os

/// Files that belong to an image and travel with it: `IMG_1.xmp`, `IMG_1.AAE`, `IMG_1.thm` for `IMG_1.JPG`.
public enum Sidecars {
    public static let extensions: Set<String> = ["xmp", "aae", "thm"]

    /// Sidecars next to `image`: same base name (any case), a sidecar extension (any case).
    /// Lists the folder once, so names keep their real case on case-insensitive volumes.
    public static func files(for image: URL) -> [URL] {
        byStem(in: list(image.deletingLastPathComponent()))[stem(of: image)] ?? []
    }

    static func list(_ folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    static func stem(of url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }

    /// Sidecars of a folder's items, keyed by lowercased base name, each list sorted by name.
    static func byStem(in items: [URL]) -> [String: [URL]] {
        Dictionary(grouping: items.filter { extensions.contains($0.pathExtension.lowercased()) }, by: stem(of:))
            .mapValues { $0.sorted { $0.lastPathComponent < $1.lastPathComponent } }
    }

    /// For a batch: lists each folder once, however many of its images ask.
    final class Finder: Sendable {
        private let folders = OSAllocatedUnfairLock<[URL: [String: [URL]]]>(initialState: [:])
        private let list: @Sendable (URL) -> [URL]

        init(list: @escaping @Sendable (URL) -> [URL] = Sidecars.list) { self.list = list }

        func files(for image: URL) -> [URL] {
            let folder = image.deletingLastPathComponent().standardizedFileURL
            // Listing under the lock: workers asking for the same folder wait for its one listing.
            return folders.withLock { cache in
                if let known = cache[folder] { return known[Sidecars.stem(of: image)] ?? [] }
                let index = Sidecars.byStem(in: list(folder))
                cache[folder] = index
                return index[Sidecars.stem(of: image)] ?? []
            }
        }
    }
}
