import Foundation

/// Rotations and flips asked for (R, L, H, V) that the picture on screen doesn't show yet: the canvas shows them
/// while the file is rewritten and decoded again.
public struct PendingChanges: Sendable {
    public private(set) var changes: [OrientationChange] = []
    /// The file being rewritten and how many of `changes` are written to it, which the next decode of it shows.
    private var writtenTo: (url: URL, count: Int)?

    public init() {}

    public var transform: PictureTransform { PictureTransform(changes) }

    public mutating func add(_ change: OrientationChange) { changes.append(change) }

    /// The next change is written to `url`; writes to another file count from zero.
    public mutating func written(_ url: URL) { writtenTo = (url, writtenCount(url) + 1) }

    /// Takes back the change whose write to `url` failed: the first not yet written (the ones before it were).
    @discardableResult
    public mutating func failed(_ url: URL) -> OrientationChange? {
        let written = writtenCount(url)
        return changes.indices.contains(written) ? changes.remove(at: written) : nil
    }

    /// A new decode of `url` is on screen. The rewritten file shows the changes written to it, so they go and
    /// the rest stay pending; another file shows none.
    public mutating func decoded(_ url: URL) {
        if let writtenTo, writtenTo.url == url {
            changes.removeFirst(min(writtenTo.count, changes.count))
        } else {
            changes = []
        }
        writtenTo = nil
    }

    public mutating func reset() { (changes, writtenTo) = ([], nil) }

    private func writtenCount(_ url: URL) -> Int { writtenTo?.url == url ? writtenTo?.count ?? 0 : 0 }
}
