import Observation

/// The window the user last worked in, falling back to one that always exists (the main viewer)
/// once that window closes. Observable, so views reading `current` redraw when it changes.
@MainActor @Observable public final class LastUsed<Item: AnyObject> {
    public let fallback: Item
    private var last: Item?

    public init(fallback: Item) { self.fallback = fallback }

    public var current: Item { last ?? fallback }

    public func use(_ item: Item) { last = item }

    /// Called when `item`'s window closes; strong until then, so it never points to a freed one.
    public func close(_ item: Item) { if last === item { last = nil } }
}
