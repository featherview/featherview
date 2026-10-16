import Foundation

/// The value of a viewer window opened for one file. Each open gets its own id: SwiftUI only
/// raises a window whose value is already open, and the same file may be opened twice.
public struct ExtraWindow: Codable, Hashable, Sendable {
    public let url: URL
    public let id: UUID

    public init(url: URL) {
        self.url = url
        id = UUID()
    }
}

/// Opens the main viewer window and extra ones from outside any view (files from Finder).
/// Only a window's view can open windows; until one installs the openers (launch, or only the
/// Batch window restored), requests wait here and are sent on install.
@MainActor public final class ViewerWindows {
    private var reveal: (() -> Void)?
    private var extra: ((ExtraWindow) -> Void)?
    private var pendingReveal = false
    private var pendingExtras: [ExtraWindow] = []

    public init() {}

    /// Shows the main viewer window, reopening it if it was closed.
    public func revealMain() {
        if let reveal { reveal() } else { pendingReveal = true }
    }

    public func openExtra(_ url: URL) {
        let window = ExtraWindow(url: url)
        if let extra { extra(window) } else { pendingExtras.append(window) }
    }

    public func install(revealMain: @escaping () -> Void, openExtra: @escaping (ExtraWindow) -> Void) {
        reveal = revealMain
        extra = openExtra
        if pendingReveal { pendingReveal = false; revealMain() }
        pendingExtras.forEach(openExtra)
        pendingExtras = []
    }
}
