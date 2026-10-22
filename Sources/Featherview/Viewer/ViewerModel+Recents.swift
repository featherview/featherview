import AppKit
import FeatherviewCore
import Observation

/// File › Open Recent and the Dock menu: the system's recent documents (plan M11 Decision 1).
/// Nothing is read on the launch path: notes made before the first `reload()` wait for it.
@MainActor @Observable
final class RecentFiles {
    static let shared = RecentFiles()

    /// Newest first, only items that still exist.
    private(set) var urls: [URL] = []
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var waiting: [URL] = []
    /// Bumped by every change, so an older reload's result never overwrites a newer list.
    @ObservationIgnored private var generation = 0

    /// On the open path: no reload, which stats every recent item.
    func note(_ url: URL) {
        guard loaded else { return waiting.append(url) }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        generation += 1
        urls = Array(([url] + urls.filter { $0.standardizedFileURL != url.standardizedFileURL })
            .prefix(NSDocumentController.shared.maximumRecentDocumentCount))
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        reload()
    }

    func reload() {
        if !loaded {
            loaded = true
            for url in waiting { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
            waiting = []
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RecentFiles.shared.reload() }
            }
        }
        generation += 1
        let current = generation
        let candidates = NSDocumentController.shared.recentDocumentURLs
        // Off the main thread: a stat on an unresponsive share or a sleeping disk can take seconds.
        Task.detached(priority: .utility) {
            let fresh = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
            await MainActor.run {
                let recents = RecentFiles.shared
                if recents.generation == current, fresh != recents.urls { recents.urls = fresh }
            }
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
