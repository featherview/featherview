import FeatherviewCore
import FeatherviewPhotos
import Foundation

/// File › Open from Photos…: an album browsed like a folder (spec "Photos library"). Its pictures are
/// `featherview-photos:` URLs, which never reach the disk: the album is their "folder".
extension ViewerModel {
    /// The list is an album's: its current or first picture is a library picture (the album's URL while it's empty).
    var isLibrary: Bool {
        (list.current ?? list.urls.first ?? folder).map(PhotosLocation.isLibrary) == true
    }

    /// The name shown for `url`: a library picture's original file name, an album's name, else the file or folder name.
    func displayName(_ url: URL) -> String {
        guard PhotosLocation.isLibrary(url) else { return url.lastPathComponent }
        if PhotosLocation.asset(of: url) != nil { return PhotosLibrary.shared.name(url) }
        let album = PhotosLocation.album(of: url)
        return photosAlbums.first { $0.id == album }?.name
            ?? String(localized: "Photos", comment: "Window title for a Photos album whose name isn't known")
    }

    /// ⇧⌘O: the album sheet, in this viewer's window.
    func showPhotos() {
        revealWindow()
        showsPhotos = true
    }

    /// Refresh (F5, ⌘R): an album is read again, a folder rescanned.
    func refresh() {
        isLibrary ? refreshPhotos() : refreshFolder()
    }

    /// Reads the album again; the picture shown stays, or, deleted in Photos, the one at its position shows,
    /// as after Move to Trash (`ImageList.reorder`).
    private func refreshPhotos() {
        // shortcut: ignored while ⌘N's unsaved image covers the album (a folder rescans after it), queue it if anyone misses it.
        guard unsaved == nil, let folder, let album = PhotosLocation.album(of: folder) else { return }
        let previous = rotateTask
        let scan = openTask
        rotateTask = Task {
            await previous?.value
            await scan?.value
            guard folder == self.folder, openTask == scan,
                  let urls = try? await PhotosLibrary.shared.list(album).urls,
                  folder == self.folder, openTask == scan, unsaved == nil else { return }
            let shown = list.current
            let removed = Set(list.urls).subtracting(urls)
            ready = ready.filter { !removed.contains($0.key) }
            knownInfo = knownInfo.filter { !removed.contains($0.key) }
            for url in removed {
                await cache.remove(url)
                await fullSizeCache.remove(url)
            }
            list.reorder(urls)
            list.release()
            emptyFolder = list.isEmpty ? folder : nil
            if list.current != shown { show() } else { focusDecodes() }
        }
    }
}
