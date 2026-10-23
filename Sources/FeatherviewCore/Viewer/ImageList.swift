import Foundation

/// The images of one folder and which one is showing. Navigation stops at both ends.
public struct ImageList: Equatable, Sendable {
    public private(set) var urls: [URL]
    public private(set) var index: Int
    /// A removed image kept on screen ("show the next image" off): it stays current, so actions
    /// reach the file the user sees, until the next key moves on; `index` already points past it.
    private var held: URL?
    public var isHolding: Bool { held != nil }

    /// Selects `current` if it is in `urls`, else the first image. Compares by name within the
    /// list's folder (resolved once, not per entry), so a symlink and its target stay separate.
    /// An exact name wins over one differing only in case (case-sensitive volumes).
    public init(urls: [URL], current: URL? = nil) {
        self.urls = urls
        guard let current, let first = urls.first,
              pathKey(current.deletingLastPathComponent()) == pathKey(first.deletingLastPathComponent())
        else { self.index = 0; return }
        let name = current.lastPathComponent
        self.index = urls.firstIndex { $0.lastPathComponent == name }
            ?? urls.firstIndex { $0.lastPathComponent.lowercased() == name.lowercased() } ?? 0
    }

    public var current: URL? { held ?? (urls.indices.contains(index) ? urls[index] : nil) }
    /// The current image, or with a removed one held, the listed one after it (where a slideshow starts).
    public var listedCurrent: URL? { urls.indices.contains(index) ? urls[index] : nil }
    public var isEmpty: Bool { urls.isEmpty }
    /// 1-based, for the window title: "3 / 120".
    public var position: String { isEmpty ? "0 / 0" : "\(index + 1) / \(urls.count)" }

    /// False (and unchanged) at the last image: the caller decides what "past the end" means.
    @discardableResult
    public mutating func next() -> Bool {
        if held != nil { held = nil; return true }  // the image after the removed one
        guard index + 1 < urls.count else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func previous() -> Bool {
        guard index > 0, !isEmpty else { return false }  // a held first image stays held
        held = nil
        index -= 1
        return true
    }

    public mutating func first() { held = nil; index = 0 }
    public mutating func last() { held = nil; index = max(urls.count - 1, 0) }
    /// Stops holding a removed image; the one after it becomes current.
    public mutating func release() { held = nil }

    /// Makes `url` current (drops a held image); false and unchanged when it isn't listed.
    public mutating func select(_ url: URL) -> Bool {
        guard let found = urls.firstIndex(of: url) else { return false }
        held = nil
        index = found
        return true
    }

    /// Takes `urls` as the list (a new sort order, a rename). The current image stays current; a held
    /// one stays held, `index` on the image that followed it; a current image no longer listed becomes
    /// held, on screen until the next key.
    public mutating func reorder(_ urls: [URL]) {
        let following = held == nil ? index + 1 : index
        if held == nil, let current, urls.contains(current) {
            self.urls = urls
            index = urls.firstIndex(of: current)!
            return
        }
        held = current
        let next = self.urls.indices.contains(following) ? self.urls[following] : nil
        self.urls = urls
        index = next.flatMap(urls.firstIndex(of:)) ?? min(index, max(urls.count - 1, 0))
    }

    /// Drops `url` (after Trash) and keeps showing the same image; if `url` was current,
    /// the following image becomes current (the previous one at the end), or with `hold`, stays
    /// current until the next move.
    public mutating func remove(_ url: URL, hold: Bool = false) {
        guard let removed = urls.firstIndex(of: url) else { return }
        if hold, url == current { held = url }
        urls.remove(at: removed)
        if removed < index || index >= urls.count { index = max(index - 1, 0) }
    }

    /// Drops several entries in one pass (Trash or a move of the grid's selection); if current goes, the next
    /// one left becomes current (the last one left at the end).
    public mutating func remove(_ removed: Set<URL>) {
        let next = urls[index...].first { !removed.contains($0) } ?? urls[..<index].last { !removed.contains($0) }
        urls.removeAll(where: removed.contains)
        index = next.flatMap(urls.firstIndex(of:)) ?? 0
    }

    /// Images up to `radius` steps either side of current, for prefetching: those ahead of a run first (`forward`:
    /// the following ones), then those behind, nearest first in each: holding → wants the next ones sooner than
    /// the ones already seen.
    public func neighbors(radius: Int, forward: Bool) -> [URL] {
        guard urls.count > 1, radius > 0 else { return [] }
        let direction = forward ? 1 : -1
        return ([direction, -direction].flatMap { sign in (1...radius).map { index + sign * $0 } })
            .filter(urls.indices.contains).map { urls[$0] }
    }
}
