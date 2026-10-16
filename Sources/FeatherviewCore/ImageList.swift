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
        held = nil
        guard index > 0, !isEmpty else { return false }
        index -= 1
        return true
    }

    public mutating func first() { held = nil; index = 0 }
    public mutating func last() { held = nil; index = max(urls.count - 1, 0) }
    /// Stops holding a removed image; the one after it becomes current.
    public mutating func release() { held = nil }

    /// Drops the current entry (after Trash); the following image becomes current.
    public mutating func removeCurrent() {
        if let current { remove(current) }
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

    /// Images up to `radius` steps either side of current, nearest first, for prefetching.
    public func neighbors(radius: Int) -> [URL] {
        guard urls.count > 1, radius > 0 else { return [] }
        var result: [URL] = []
        for step in 1...radius {
            for offset in [step, -step] where urls.indices.contains(index + offset) {
                result.append(urls[index + offset])
            }
        }
        return result
    }
}
