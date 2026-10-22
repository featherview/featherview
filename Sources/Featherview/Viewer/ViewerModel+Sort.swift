import Foundation
import FeatherviewCore

/// View › Sort By: the list in the stored order, re-sorted in place with the picture kept.
extension ViewerModel {
    /// Re-sorts the list in `SortOrder.stored()`, after the open running (its list would replace this one).
    /// Values are read and the list sorted off the main thread: 10,000 files take ~100–160 ms to sort.
    /// shortcut: a cancelled re-sort still finishes its read (ImageSort.values doesn't check cancellation), make
    /// it check if switching orders on a slow disk queues up reads.
    func applySortOrder() {
        sortTask?.cancel()
        let scan = openTask
        sortTask = Task {
            await scan?.value
            while !Task.isCancelled {
                let order = SortOrder.stored()
                let urls = list.urls
                let cached = order.key == sortValuesKey ? sortValues : [:]
                let (sorted, values) = await Task.detached(priority: order.readsFileHeaders ? .utility : .userInitiated) {
                    ImageSort.resorted(urls, by: order, cached: cached)
                }.value
                guard !Task.isCancelled else { return }
                sortValues = values
                sortValuesKey = order.key
                guard list.urls == urls else { continue }  // a file came or went meanwhile: sort the list as it is now
                relist(sorted)
                return
            }
        }
    }

    /// Takes `sorted` as the list. The current image stays on screen; only its neighbours change.
    func relist(_ sorted: [URL]) {
        list.reorder(sorted)
        let neighbors = focusDecodes()
        guard zoom == .fit, !neighbors.isEmpty else { return }
        Task { await cache.prefetch(neighbors, target: .fit(screens)) }
    }
}
