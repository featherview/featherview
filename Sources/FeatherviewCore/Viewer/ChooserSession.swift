import Foundation
import Observation

/// The folder chooser while it is open. Listing a folder reads the disk (slow on a share or in a big
/// folder), so it runs off the main thread; every key queues up and applies in order, after the
/// listings before it.
@MainActor @Observable
public final class ChooserSession {
    /// nil until the first listing is done, and after `close()`.
    public private(set) var chooser: FolderChooser?
    /// True from `start` to `close`, also while the first listing runs, so keys go to the chooser.
    public private(set) var isOpen = false
    /// Called after each listing, e.g. to count the listed folders' images.
    @ObservationIgnored public var onListed: @MainActor () -> Void = {}
    /// Bumped by `close()`, so queued keys and a listing still running are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func start(folder: URL, includeHidden: Bool) {
        close()
        isOpen = true
        list { $0 = FolderChooser(folder: folder, includeHidden: includeHidden) }
    }

    /// ↑ ↓ select, → / Space enter, ← up, Return opens.
    public func move(_ delta: Int) { enqueue { $0.chooser?.moveSelection(by: delta) } }
    public func enter() { list { $0?.enter() } }
    public func up() { list { $0?.up() } }
    public func open(_ action: @escaping @MainActor (URL) -> Void) {
        enqueue { if let url = $0.chooser?.selected.url { action(url) } }
    }

    public func close() {
        generation += 1
        isOpen = false
        chooser = nil
    }

    /// Waits until every queued key has applied.
    public func settled() async { await task?.value }

    private func list(_ change: @escaping @Sendable (inout FolderChooser?) -> Void) {
        enqueue { session in
            let generation = session.generation
            let current = session.chooser
            let updated = await Task.detached(priority: .userInitiated) {
                var chooser = current
                change(&chooser)
                return chooser
            }.value
            guard generation == session.generation else { return }
            session.chooser = updated
            session.onListed()
        }
    }

    private func enqueue(_ step: @escaping @MainActor (ChooserSession) async -> Void) {
        let previous = task
        let generation = generation
        task = Task {
            await previous?.value
            guard generation == self.generation else { return }
            await step(self)
        }
    }
}
