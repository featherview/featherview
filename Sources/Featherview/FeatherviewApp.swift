import FeatherviewCore
import SwiftUI

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewer = ViewerModel()
    @State private var batch = BatchModel()

    var body: some Scene {
        Window("Featherview", id: "viewer") {
            ViewerView(model: viewer)
                .onAppear { appDelegate.onOpen = { viewer.open($0) } }
        }
        .commands { ViewerCommands(model: viewer) }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch, viewer: viewer)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder can hand us a file before the window exists; hold it until the window is ready.
    var onOpen: ((URL) -> Void)? {
        didSet {
            if let onOpen, let pending {
                self.pending = nil
                onOpen(pending)
            }
        }
    }

    private var pending: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let onOpen { onOpen(url) } else { pending = url }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
