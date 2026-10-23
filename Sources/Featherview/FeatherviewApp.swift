import FeatherviewCore
import FeatherviewJXL
import SwiftUI
import UniformTypeIdentifiers

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        ImageEncoder.jxlEncoder = JXLEncoder.encode
        // AppKit mirrors only for a right-to-left system language, not for one picked for this app alone.
        if let language = Bundle.main.preferredLocalizations.first,
           Locale.Language(identifier: language).characterDirection == .rightToLeft {
            let defaults = UserDefaults.standard
            let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments.merging(["AppleTextDirection": true]) { given, _ in given },
                                       forName: UserDefaults.argumentDomain)
        }
    }

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
            // Built when the window first opens: its settings and presets stay off the launch path.
            let batch = BatchModel.shared
            BatchView(model: batch)
                .onAppear {
                    appDelegate.isBusy = { batch.isRunning }
                    appDelegate.stopBatch = { await batch.stopAndWait() }
                    appDelegate.willQuit = { batch.saveNow() }
                }
                // A relaunch opens the viewer, never the batch window (its settings are saved on their own).
                .background(WindowAccessor { $0.isRestorable = false })
                .modifier(OpensViewerWindows())
        }
        .defaultSize(width: 1100, height: 700)
        // Batch Convert… (B) and Featherview › About open these: no second item in the Window menu.
        .commandsRemoved()

        Window("About Featherview", id: "about") {
            AboutView()
                .modifier(OpensViewerWindows())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
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
/// and the action Settings › Browsing shares with it.
@MainActor
enum DefaultViewerOffer {
    private static var scheduled = false

    /// Bundle identifier of the app that opens `type` now, nil for none.
    static func handler(for type: UTType) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: type).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// Name of the app that opens `type` now, nil for none.
    static func appName(for type: UTType) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: type).map { FileManager.default.displayName(atPath: $0.path) }
    }

    static func opensWithFeatherview(_ type: UTType) -> Bool { handler(for: type) == Bundle.main.bundleIdentifier }

    private static var opensCache: [UTType: Bool] = [:]
    private static var clearsCacheOnActivation: NSObjectProtocol?

    /// `opensWithFeatherview` asked once per type, for the File menu, which is rebuilt on every image.
    /// Forgotten after a claim and when the app becomes active (another app may have taken the type).
    static func cachedOpensWithFeatherview(_ type: UTType) -> Bool {
        if clearsCacheOnActivation == nil {
            clearsCacheOnActivation = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { opensCache = [:] }
            }
        }
        if let known = opensCache[type] { return known }
        let opens = opensWithFeatherview(type)
        opensCache[type] = opens
        return opens
    }

    /// Makes Featherview the default for `type`. From macOS 26.4 macOS confirms it in a prompt of its own,
    /// one per type, which is why every click claims a single type. No message afterwards: Keep in that
    /// prompt and a refusal look alike, and Settings › Browsing shows which app opens the type.
    static func claim(_ type: UTType) async {
        try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        opensCache[type] = nil
    }

    /// Asks once, after the first window is up and its first image (if any) is on screen, never on the launch path.
    static func showOnce() {
        guard !scheduled else { return }
        scheduled = true
        Task {
            while ViewerModel.main.isOpening { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(100))  // the frame with the image commits first
            RecentFiles.shared.reload()
            guard DefaultViewer.shouldOffer(bundleURL: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser,
                                            offeredBefore: AppSettings.offeredDefaultViewer.value(),
                                            jpegHandler: handler(for: .jpeg)) else { return }
            // Set before asking, so a crash or quit never asks twice.
            UserDefaults.standard.set(true, forKey: AppSettings.offeredDefaultViewer.key)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Open JPEG images with Featherview?")
            alert.informativeText = String(localized: "Featherview can open them instead of Preview. Other image types can follow in Settings › Browsing.")
            alert.addButton(withTitle: String(localized: "Use Featherview"))
            alert.addButton(withTitle: String(localized: "Not Now")).keyEquivalent = "\u{1b}"
            if alert.runModal() == .alertFirstButtonReturn { await claim(.jpeg) }
        }
    }
}

/// A viewer window of its own, opened for one file; restored windows reopen their file.
struct ExtraViewer: View {
    let url: URL?
    @State private var model = ViewerModel()

    var body: some View {
        ViewerView(model: model)
            // Not remembered: a restored window isn't the user opening a file; Finder's files are noted in openDocuments.
            .onAppear { if let url, model.list.current == nil { model.open(url, remember: false) } }
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
        Theme.apply(AppSettings.appearanceMode)
        MenuKeys.install()
        OwnDecoders.register(SVGFormat.format)
        // AppKit hands Finder's files to application(_:open:) only after SwiftUI built the window
        // (~50 ms later); taking the open event here lets the image decode meanwhile.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.scheduleAutomaticCheck()
        // Open Recent also when no viewer window comes back (showOnce reads it sooner when one does).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { RecentFiles.shared.reload() }
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = (1...max(list.numberOfItems, 1)).compactMap {
            list.atIndex($0)?.coerce(toDescriptorType: typeFileURL)?.fileURLValue
        }
        for (index, url) in urls.enumerated() {
            // The main window takes the first file while it has none (launch) or no viewer window is open;
            // every other file gets a window.
            let mainIsEmpty = viewer.list.current == nil && !viewer.isOpening && viewer.emptyFolder == nil && viewer.unsaved == nil
            if index == 0, ViewerModel.windows.mainTakesFile(mainIsEmpty: mainIsEmpty) {
                viewer.open(url)
            } else {
                RecentFiles.shared.note(url)
                ViewerModel.windows.openExtra(url)
            }
        }
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = ViewerModel.all.allObjects.filter { UnsavedRules.asksFirst(.quit, hasUnsaved: $0.unsaved != nil) }
        if !unsaved.isEmpty {
            Task {
                for model in unsaved {
                    guard await model.confirmDiscard() else { return sender.reply(toApplicationShouldTerminate: false) }
                    model.show()  // the covered image, should the quit be cancelled after all
                }
                // Asked about every image: the batch check comes next.
                switch applicationShouldTerminate(sender) {
                case .terminateNow: sender.reply(toApplicationShouldTerminate: true)
                case .terminateCancel: sender.reply(toApplicationShouldTerminate: false)
                default: break  // the batch replies once it has stopped
                }
            }
            return .terminateLater
        }
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
