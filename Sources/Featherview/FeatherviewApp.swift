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
        .commands { ViewerCommands(model: appDelegate.viewer) }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch, viewer: appDelegate.viewer)
                .onAppear { appDelegate.isBusy = { batch.isRunning } }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here, not by a view, so a file from Finder starts decoding before any window exists.
    let viewer = ViewerModel()
    /// True while a batch runs: quitting then would stop it part-way. Set by the Batch window.
    var isBusy: () -> Bool = { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit hands Finder's files to application(_:open:) only after SwiftUI built the window
        // (~50 ms later); taking the open event here lets the image decode meanwhile.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.atIndex(1)?
            .coerce(toDescriptorType: typeFileURL)?.fileURLValue else { return }
        viewer.open(url)
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }
}
