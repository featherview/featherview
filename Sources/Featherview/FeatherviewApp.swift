import FeatherviewCore
import SwiftUI

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var batch = BatchModel()

    var body: some Scene {
        Window("Featherview", id: "viewer") {
            ViewerView(model: appDelegate.viewer)
        }
        .commands { ViewerCommands() }

        // Files opened from Finder while the main viewer shows an image, each with its own folder list.
        WindowGroup("Featherview", id: "viewer-extra", for: URL.self) { $url in
            ExtraViewer(url: url)
        }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch)
                .onAppear { appDelegate.isBusy = { batch.isRunning } }
        }

        Settings {
            SettingsView()
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
    let viewer = ViewerModel()
    /// True while a batch runs: quitting then would stop it part-way. Set by the Batch window.
    var isBusy: () -> Bool = { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
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
                ViewerModel.openWindow(url)
            }
        }
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }
}
