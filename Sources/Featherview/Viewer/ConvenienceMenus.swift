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

/// Whether the clipboard holds something New from Clipboard opens: re-checked when the app becomes active and
/// after Featherview's own ⌘C, never before the first image is on screen.
@MainActor @Observable
final class ClipboardWatch {
    static let shared = ClipboardWatch()
    private(set) var hasImage = false

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ClipboardWatch.shared.recheck() }
        }
        // Made when the menu is first built, which may be after the launch's activation.
        recheck()
    }

    func recheck() {
        Task {
            // Not on the launch path: the first image draws first.
            while ViewerModel.main.isOpening { try? await Task.sleep(for: .milliseconds(50)) }
            let pasteboard = NSPasteboard.general
            let has = Self.fileURL(pasteboard) != nil || Self.imageType(pasteboard) != nil
            if hasImage != has { hasImage = has }
        }
    }

    /// A copied file Featherview reads (Finder's Copy).
    static func fileURL(_ pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first.flatMap { ImageFormats.isDecodable($0) ? $0 : nil }
    }

    /// The first image type on the clipboard that ImageIO decodes.
    static func imageType(_ pasteboard: NSPasteboard) -> String? {
        ClipboardImage.preferredType(pasteboard.types?.map(\.rawValue) ?? [])
    }
}
