import Foundation

/// File › Open Recent's entries, newest first (plan M11 Decision 1). A reload checks the entries
/// off the main thread; files noted while it runs go first in its result, so neither side is lost.
public struct RecentList: Sendable {
    public private(set) var urls: [URL] = []
    private var generation = 0
    private var notedSinceReload: [URL] = []

    public init() {}

    public mutating func note(_ url: URL, limit: Int) {
        notedSinceReload = Self.merge([url], notedSinceReload, limit: limit)
        urls = Self.merge([url], urls, limit: limit)
    }

    /// Call right before reading the system's list; pass the token to `finishReload`.
    public mutating func startReload() -> Int {
        generation += 1
        notedSinceReload = []
        return generation
    }

    /// `fresh`: the entries as read at `startReload`, gone items left out. An older reload's result is dropped.
    public mutating func finishReload(_ fresh: [URL], token: Int, limit: Int) {
        guard token == generation else { return }
        let merged = Self.merge(notedSinceReload, fresh, limit: limit)
        if merged != urls { urls = merged }
    }

    /// Missing, or in a Trash (the system's bookmark follows a trashed file there). Stats the file.
    public static func isGone(_ url: URL) -> Bool {
        let parts = url.pathComponents
        return parts.contains(".Trash") || parts.contains(".Trashes") || !FileManager.default.fileExists(atPath: url.path)
    }

    /// What Featherview opens: an image (by extension) or a folder. A dropped notes.txt isn't listed.
    public static func isRememberable(_ url: URL) -> Bool {
        ImageFormats.isDecodable(url)
            || (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func merge(_ first: [URL], _ rest: [URL], limit: Int) -> [URL] {
        var seen = Set<String>()
        return Array((first + rest).filter { seen.insert($0.standardizedFileURL.path).inserted }.prefix(limit))
    }
}
