import Foundation

/// The images of one folder and which one is showing. Navigation stops at both ends.
public struct ImageList: Equatable, Sendable {
    public private(set) var urls: [URL]
    public private(set) var index: Int

    /// Selects `current` if it is in `urls` (compared by `pathKey`), else the first image.
    public init(urls: [URL], current: URL? = nil) {
        self.urls = urls
        let target = current.map(pathKey)
        self.index = urls.firstIndex { pathKey($0) == target } ?? 0
    }

    public var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    public var isEmpty: Bool { urls.isEmpty }
    /// 1-based, for the window title: "3 / 120".
    public var position: String { isEmpty ? "0 / 0" : "\(index + 1) / \(urls.count)" }

    /// False (and unchanged) at the last image: the caller decides what "past the end" means.
    @discardableResult
    public mutating func next() -> Bool {
        guard index + 1 < urls.count else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func previous() -> Bool {
        guard index > 0, !isEmpty else { return false }
        index -= 1
        return true
    }

    public mutating func first() { index = 0 }
    public mutating func last() { index = max(urls.count - 1, 0) }

    /// Drops the current entry (after Trash); the following image becomes current.
    public mutating func removeCurrent() {
        guard !isEmpty else { return }
        urls.remove(at: index)
        if index >= urls.count { index = max(urls.count - 1, 0) }
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
