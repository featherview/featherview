import AppKit
import FeatherviewCore
import SwiftUI

/// File › New from Clipboard (⌘N): the focused viewer, else the one last used.
struct ClipboardCommand: View {
    let model: ViewerModel?

    var body: some View {
        Button("New from Clipboard") { (model ?? ViewerModel.lastActive.current).newFromClipboard() }
            .keyboardShortcut("n")
            .disabled(!ClipboardWatch.shared.hasImage)
    }
}

/// Whether the clipboard holds something New from Clipboard opens: re-checked when the app becomes active, after
/// Featherview's own ⌘C, when a menu opens and on ⌘N, never before the first image is on screen.
@MainActor @Observable
final class ClipboardWatch {
    static let shared = ClipboardWatch()
    private(set) var hasImage = false
    /// The clipboard's `changeCount` when it was last read.
    @ObservationIgnored private var seen = -1

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ClipboardWatch.shared.recheck() }
        }
        // The clipboard also changes while Featherview stays in front (⌃⇧⌘4, Universal Clipboard, a clipboard manager).
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ClipboardWatch.shared.refresh() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                  event.charactersIgnoringModifiers == "n" else { return event }
            let handled = MainActor.assumeIsolated {
                let watch = ClipboardWatch.shared, had = watch.hasImage
                watch.refresh()
                // The menu item takes the new state on SwiftUI's next update, too late for this key: act as it would.
                guard watch.hasImage != had, NSApp.modalWindow == nil else { return false }
                if watch.hasImage { ViewerModel.lastActive.current.newFromClipboard() } else { NSSound.beep() }
                return true
            }
            return handled ? nil : event
        }
        // Made when the menu is first built, which may be after the launch's activation.
        recheck()
    }

    func recheck() {
        Task {
            // Not on the launch path: the first image draws first.
            while ViewerModel.main.isOpening { try? await Task.sleep(for: .milliseconds(50)) }
            refresh()
        }
    }

    /// Reads the clipboard again if it changed since it was last read.
    func refresh() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != seen else { return }
        seen = pasteboard.changeCount
        let has = Self.content(pasteboard) != nil
        if hasImage != has { hasImage = has }
    }

    /// A copied file Featherview reads (Finder's Copy), else the first image type ImageIO decodes.
    static func content(_ pasteboard: NSPasteboard) -> ClipboardImage.Content? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return ClipboardImage.content(fileURLs: urls ?? [], types: pasteboard.types?.map(\.rawValue) ?? [])
    }
}
