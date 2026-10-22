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
        sortedOrder = .stored()
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
                takeOrder(sorted)
                return
            }
        }
    }

    /// Takes `urls` as the list in the stored order: files no longer in `urls` leave, new ones go in at their place
    /// (with `sortValues`), so a rename or an arriving file costs a few comparisons, not a sort on the main thread.
    /// The current image stays on screen; only its neighbours change.
    func relist(_ urls: [URL]) {
        let wanted = Set(urls)
        let kept = list.urls.filter(wanted.contains)
        let listed = Set(kept)
        takeOrder(ImageSort.inserting(urls.filter { !listed.contains($0) }, into: kept, by: .stored(), values: sortValues))
    }

    /// Reads and keeps the stored key's values for `urls` (new or renamed files), off the main thread.
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

    /// Takes `sorted`, already in the stored order, as the list (a re-sort sorted it off the main thread).
    private func takeOrder(_ sorted: [URL]) {
        list.reorder(sorted)
        let neighbors = focusDecodes()
        guard zoom == .fit, !neighbors.isEmpty else { return }
        Task { await cache.prefetch(neighbors, target: .fit(screens)) }
    }
}
