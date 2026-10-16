import FeatherviewCore
import SwiftUI

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var batch = BatchModel()

    var body: some Scene {
        Window("Featherview", id: "viewer") {
            ViewerView(model: appDelegate.viewer)
                .modifier(OpensViewerWindows())
        }
        .commands { ViewerCommands() }

        // Files opened from Finder while the main viewer shows an image, each with its own folder list.
        WindowGroup("Featherview", id: "viewer-extra", for: ExtraWindow.self) { $window in
            ExtraViewer(url: window?.url)
                .modifier(OpensViewerWindows())
        }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch)
                .onAppear { appDelegate.isBusy = { batch.isRunning } }
                .modifier(OpensViewerWindows())
        }

        Settings {
            SettingsView()
        }
    }
}

/// Any window can open viewer windows: state restoration may bring back only the Batch window
/// or an extra viewer, and files from Finder still need the main window.
struct OpensViewerWindows: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            ViewerModel.windows.install(revealMain: { [openWindow] in openWindow(id: "viewer") },
                                        openExtra: { [openWindow] in openWindow(id: "viewer-extra", value: $0) })
        }
    }
}

/// A viewer window of its own, opened for one file; restored windows reopen their file.
struct ExtraViewer: View {
    let url: URL?
    @State private var model = ViewerModel()

    var body: some View {
        ViewerView(model: model)
            .onAppear { if let url, model.list.current == nil { model.open(url) } }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here, not by a view, so a file from Finder starts decoding before any window exists.
    let viewer: ViewerModel = {
        let viewer = ViewerModel()
        viewer.revealWindow = { ViewerModel.windows.revealMain() }
        return viewer
    }()
    /// True while a batch runs: quitting then would stop it part-way. Set by the Batch window.
    var isBusy: () -> Bool = { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        // ⌘O from the Batch window before any viewer was used opens in the main one.
        ViewerModel.lastActive = viewer
        // AppKit hands Finder's files to application(_:open:) only after SwiftUI built the window
        // (~50 ms later); taking the open event here lets the image decode meanwhile.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = (1...max(list.numberOfItems, 1)).compactMap {
            list.atIndex($0)?.coerce(toDescriptorType: typeFileURL)?.fileURLValue
        }
        for url in urls {
            // The main window takes the first file while it has none (launch); every other file gets a window.
            if viewer.list.current == nil, !viewer.isOpening, viewer.emptyFolder == nil {
                viewer.open(url)
            } else {
                ViewerModel.windows.openExtra(url)
            }
        }
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }
}
