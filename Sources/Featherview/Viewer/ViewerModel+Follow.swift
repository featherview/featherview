import Foundation
import FeatherviewCore

/// View › Follow New Files (plan M11 Decision 8): while on, the window watches its folder, lists what arrives
/// and shows the newest arrival once it's complete. The watch runs only while following.
extension ViewerModel {
    /// Watches `folder` while following (again after an open moved it); stops the watch otherwise.
    func watchFolder() {
        folderWatch?.cancel()
        folderWatch = nil
        followTask?.cancel()
        pendingRescan = false
        guard followsNewFiles else { return }
        guard let folder, let watch = FolderWatch(folder: folder, onChange: { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }, onGone: { [weak self] in
            Task { @MainActor in self?.folderGone() }
        }) else {
            followsNewFiles = false
            return
        }
        folderWatch = watch
    }

    /// Rescans the folder, takes its new and vanished images into the list in sort order, then shows the newest
    /// arrival once complete. Queued behind rotations, moves, Trash and the open's scan, which change the list too.
    func folderChanged() {
        guard followsNewFiles, let folder else { return }
        followTask?.cancel()
        if unsaved != nil {
            pendingRescan = true
            return
        }
        let previous = rotateTask
        let scan = openTask
        rotateTask = Task {
            await previous?.value
            await scan?.value
            guard followsNewFiles, folder == self.folder, openTask == scan, unsaved == nil else { return }
            let listed = list.urls
            // Around the current file, the scan names files as the list does (a file's folder isn't symlink-resolved).
            let around = list.current ?? folder
            let includeHidden = AppSettings.showHiddenFiles.value()
            let found = await Task.detached(priority: .userInitiated) { () -> (scanned: [URL], added: [URL], removed: [URL], newest: URL?)? in
                guard let scanned = try? FolderScanner.images(around: around, includeHidden: includeHidden, sorted: false)
                else { return nil }
                let (added, removed) = Arrivals.diff(listed: listed, scanned: scanned)
                let newest = Arrivals.newest(added) {
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                }
                return (scanned, added, removed, newest)
            }.value
            guard let found, followsNewFiles, openTask == scan, unsaved == nil else { return }
            let removed = Set(found.removed)
            if !removed.isEmpty {
                ready = ready.filter { !removed.contains($0.key) }
                knownInfo = knownInfo.filter { !removed.contains($0.key) }
                sortValues = sortValues.filter { !removed.contains($0.key) }
                for url in removed {
                    await cache.remove(url)
                    await fullSizeCache.remove(url)
                }
            }
            await readSortValues(for: found.added)
            // An open while the values were read has the newer list.
            guard openTask == scan, unsaved == nil else { return }
            // A current file deleted elsewhere stays on screen, held, until the next key (ImageList.reorder).
            relist(found.scanned)
            if !list.isEmpty { emptyFolder = nil }
            guard let newest = found.newest else { return }
            followTask?.cancel()  // an earlier queued rescan's wait
            followTask = Task {
                guard await Arrivals.settled(newest), !Task.isCancelled, followsNewFiles,
                      // The list takes arrivals; the window stays while something else is up.
                      !isChooserOpen, destinationPanel == nil, unsaved == nil, !renaming,
                      list.select(newest) else { return }
                show()
            }
        }
    }

    /// The folder itself was renamed or deleted.
    func folderGone() {
        followsNewFiles = false
    }
}
