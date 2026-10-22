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
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var checkAgain = false
    /// One serial queue, not the cooperative pool: a stat on a hung share blocks one thread until it times out,
    /// never the threads decoding and prefetching run on.
    private static let statQueue = DispatchQueue(label: "net.mynetx.featherview.recents", qos: .utility)

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
        // A new generation also drops the result of a check still running.
        list.finishReload([], token: list.startReload(), limit: limit)
    }

    /// Drops entries gone from disk; on activation and after the app's own Trash and move. The first check reads
    /// the system's list; later ones check the entries off the main thread and re-read the system's list only when
    /// one is missing, as its bookmark follows a moved or renamed file to its new path. At most one check runs;
    /// calls meanwhile make it run once more.
    func reload() {
        let readsSystem = !loaded
        if !loaded {
            loaded = true
            for url in waiting { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
            waiting = []
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RecentFiles.shared.reload() }
            }
        }
        check(readingSystem: readsSystem)
    }

    private func check(readingSystem: Bool) {
        guard !checking else { checkAgain = true; return }
        checking = true
        let token = list.startReload()
        // On the main thread, as NSDocumentController must be: its getter resolves every bookmark, which a stale
        // entry on a dropped share can make slow. So only the first check reads it, and a check that found an
        // entry missing; a plain ⌘-Tab never does.
        let candidates = readingSystem ? NSDocumentController.shared.recentDocumentURLs : list.urls
        let limit = limit
        Self.statQueue.async {
            let fresh = candidates.filter { !RecentList.isGone($0) }
            Task { @MainActor in
                RecentFiles.shared.finishCheck(fresh, missing: fresh.count < candidates.count && !readingSystem,
                                               token: token, limit: limit)
            }
        }
    }

    private func finishCheck(_ fresh: [URL], missing: Bool, token: Int, limit: Int) {
        checking = false
        // A missing entry may have moved: the system's list knows where to.
        if missing { return check(readingSystem: true) }
        list.finishReload(fresh, token: token, limit: limit)
        if checkAgain {
            checkAgain = false
            check(readingSystem: false)
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
