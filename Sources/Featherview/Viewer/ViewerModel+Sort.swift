import Foundation
import FeatherviewCore

/// View › Sort By: the list in the stored order, re-sorted in place with the picture kept.
extension ViewerModel {
    /// Re-sorts the list in `SortOrder.stored()`, after the open running (its list would replace this one).
    func applySortOrder() {
        sortTask?.cancel()
        let scan = openTask
        sortTask = Task {
            await scan?.value
            guard !Task.isCancelled else { return }
            if SortOrder.stored().key != sortValuesKey { sortValues = [:] }
            await readSortValues(for: list.urls.filter { sortValues[$0] == nil })
            guard !Task.isCancelled else { return }
            relist(list.urls)
        }
    }

    /// Takes `urls` as the list in the stored order. The current image stays on screen; only its neighbours change.
    func relist(_ urls: [URL]) {
        list.reorder(ImageSort.sorted(urls, by: .stored(), values: sortValues))
        let neighbors = focusDecodes()
        guard zoom == .fit, !neighbors.isEmpty else { return }
        Task { await cache.prefetch(neighbors, target: .fit(screens)) }
    }

    /// Reads and keeps the stored key's values for `urls` (new or renamed files), off the main thread.
    /// shortcut: a cancelled re-sort still finishes its read (ImageSort.values doesn't check cancellation), make
    /// it check if switching orders on a slow disk queues up reads.
    func readSortValues(for urls: [URL]) async {
        let key = SortOrder.stored().key
        if key != sortValuesKey {
            sortValues = [:]
            sortValuesKey = key
        }
        guard key != .name, !urls.isEmpty else { return }
        let read = await Task.detached(priority: key == .dateTaken ? .utility : .userInitiated) {
            ImageSort.values(of: urls, key: key)
        }.value
        guard key == sortValuesKey else { return }  // the order changed while reading
        sortValues.merge(read) { $1 }
    }
}
