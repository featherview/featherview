import AppKit
import FeatherviewCore
import Observation

/// File › Open Recent and the Dock menu: the system's recent documents (plan M11 Decision 1).
/// Nothing is read on the launch path: notes made before the first `reload()` wait for it.
@MainActor @Observable
final class RecentFiles {
    static let shared = RecentFiles()

    /// Newest first, only items that still exist.
    var urls: [URL] { list.urls }
    private var list = RecentList()
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var waiting: [URL] = []

    private var limit: Int { NSDocumentController.shared.maximumRecentDocumentCount }

    /// On the open path: no reload, which stats every recent item. A gone file (a stale entry chosen) isn't
    /// noted again; the reload drops its entry.
    func note(_ url: URL) {
        guard RecentList.isRememberable(url) else { return }
        guard loaded else { return waiting.append(url) }
        guard !RecentList.isGone(url) else { return reload() }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        list.note(url, limit: limit)
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        reload()
    }

    /// Also after the app's own Trash and move: the system's bookmark follows a moved file to its new path.
    func reload() {
        if !loaded {
            loaded = true
            for url in waiting { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
            waiting = []
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RecentFiles.shared.reload() }
            }
        }
        let token = list.startReload()
        let candidates = NSDocumentController.shared.recentDocumentURLs
        let limit = limit
        // Off the main thread: a stat on an unresponsive share or a sleeping disk can take seconds.
        Task.detached(priority: .utility) {
            let fresh = candidates.filter { !RecentList.isGone($0) }
            await MainActor.run { RecentFiles.shared.list.finishReload(fresh, token: token, limit: limit) }
        }
    }
}

extension ViewerModel {
    /// The current file on every screen, filling it (Decision 5). The call only records the choice.
    func setDesktopPicture() {
        guard availability.canSetDesktop, let url = list.current else { return }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]
        do {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            }
        } catch {
            errorMessage = String(localized: "Couldn't set \(url.lastPathComponent) as the desktop picture")
        }
    }
}
