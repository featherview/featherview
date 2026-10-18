import FeatherviewCore
import SwiftUI
import UniformTypeIdentifiers

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

        Window("Batch", id: "batch") {
            BatchView(model: batch)
                .onAppear {
                    appDelegate.isBusy = { batch.isRunning }
                    appDelegate.stopBatch = { await batch.stopAndWait() }
                    appDelegate.willQuit = { batch.saveNow() }
                }
                .modifier(OpensViewerWindows())
        }
        .defaultSize(width: 1100, height: 700)

        Window("About Featherview", id: "about") {
            AboutView()
                .modifier(OpensViewerWindows())
        }
        .windowResizability(.contentSize)
    }
}

/// Any window can open viewer windows: state restoration may bring back only the Batch or About window
/// or an extra viewer, and files from Finder still need the main window. The menu bar installs them too
/// (`ViewerCommands`), for a launch that restores no window at all.
struct OpensViewerWindows: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            Self.install(openWindow)
            DefaultViewerOffer.showOnce()
        }
    }

    static func install(_ openWindow: OpenWindowAction) {
        ViewerModel.windows.install(revealMain: {
                                        openWindow(id: "viewer")
                                        // openWindow leaves a minimized window in the Dock, also one restored minimized at launch.
                                        NSApp.windows.first { $0.identifier?.rawValue == "viewer" && $0.isMiniaturized }?
                                            .deminiaturize(nil)
                                    },
                                    openExtra: { openWindow(id: "viewer-extra", value: $0) })
    }
}

/// Making Featherview the default app for images (spec "Viewer › Default viewer"): the launch offer,
/// and the action Preferences › Browsing shares with it.
@MainActor
enum DefaultViewerOffer {
    private static var scheduled = false

    /// Bundle identifier of the app that opens `type` now, nil for none.
    static func handler(for type: UTType) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: type).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    static var typesToClaim: [UTType] {
        DefaultViewer.typesToClaim(DefaultViewer.readableTypes, ownID: Bundle.main.bundleIdentifier ?? "", handler: handler)
    }

    /// Sets Featherview as the default for every type it may take; names the types macOS refused.
    static func claim() async {
        var failed: [UTType] = []
        for type in typesToClaim {
            do { try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) } catch { failed.append(type) }
        }
        guard !failed.isEmpty else { return }
        let names = failed.map { $0.preferredFilenameExtension?.uppercased() ?? $0.identifier }.formatted(.list(type: .and))
        let alert = NSAlert()
        alert.messageText = String(localized: "Featherview couldn't become the default for \(names).")
        alert.runModal()
    }

    /// Asks once, after the first window is up and its first image (if any) is on screen, never on the launch path.
    static func showOnce() {
        guard !scheduled else { return }
        scheduled = true
        Task {
            while ViewerModel.main.isOpening { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(100))  // the frame with the image commits first
            guard DefaultViewer.shouldOffer(bundleURL: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser,
                                            offeredBefore: AppSettings.offeredDefaultViewer.value(),
                                            jpegHandler: handler(for: .jpeg)) else { return }
            // Set before asking, so a crash or quit never asks twice.
            UserDefaults.standard.set(true, forKey: AppSettings.offeredDefaultViewer.key)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Open your images with Featherview?")
            alert.informativeText = String(localized: "Featherview can open your images instead of Preview. You can change this later in Preferences › Browsing.")
            alert.addButton(withTitle: String(localized: "Use Featherview"))
            alert.addButton(withTitle: String(localized: "Not Now")).keyEquivalent = "\u{1b}"
            if alert.runModal() == .alertFirstButtonReturn { await claim() }
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
            .onDisappear { ViewerModel.lastActive.close(model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewer = ViewerModel.main
    /// True while a batch runs: quitting then would stop it part-way. Set by the Batch window.
    var isBusy: () -> Bool = { false }
    /// Stops the batch and returns once the files being written are committed.
    var stopBatch: @MainActor () async -> Void = {}
    /// Writes state that is saved with a delay (the batch settings).
    var willQuit: () -> Void = {}

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        MenuKeys.install()
        OwnDecoders.register(SVGFormat.format)
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
        for (index, url) in urls.enumerated() {
            // The main window takes the first file while it has none (launch) or no viewer window is open;
            // every other file gets a window.
            let mainIsEmpty = viewer.list.current == nil && !viewer.isOpening && viewer.emptyFolder == nil
            if index == 0, ViewerModel.windows.mainTakesFile(mainIsEmpty: mainIsEmpty) {
                viewer.open(url)
            } else {
                ViewerModel.windows.openExtra(url)
            }
        }
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isBusy() {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit while the batch is running?")
            alert.informativeText = String(localized: "Files not converted yet are left as they are.")
            alert.addButton(withTitle: String(localized: "Keep Running"))
            alert.addButton(withTitle: String(localized: "Quit"))
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            // A file being written would leave its temp file behind if the process exited now.
            Task {
                await stopBatch()
                willQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        willQuit()
        return .terminateNow
    }
}
