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

    func note(_ url: URL) {
        guard loaded else { return waiting.append(url) }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        reload()
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
        let fresh = NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if fresh != urls { urls = fresh }
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
