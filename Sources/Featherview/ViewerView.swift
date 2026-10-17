import FeatherviewCore
import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool
    @Environment(\.controlActiveState) private var activeState
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @State private var panController = PanController()
    /// Toolbar buttons are built only after the first image (or message) is on screen: building them takes
    /// ~130 ms of the main thread, and in the same update they'd hold back that frame at launch (budget 350 ms).
    @State private var toolbarReady = false
    @AppStorage(AppSettings.backgroundColor.key) private var backgroundHex = AppSettings.backgroundColor.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var overlayTemplate = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue
    @AppStorage(toolbarHiddenKey) private var toolbarHidden = false
    @AppStorage(statusBarHiddenKey) private var statusBarHidden = false

    private var background: Color { Color(nsColor: backgroundNSColor) }
    private var backgroundNSColor: NSColor {
        guard let c = HexColor.parse(backgroundHex) else { return .black }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if let image = model.image {
                ImageCanvas(image: image, size: drawSize(image), pixelWidth: pixelSize(image).width,
                            displayScale: displayScale, background: backgroundNSColor,
                            checkerboard: checkerboard, panController: panController,
                            onDoubleClick: model.toggleFullScreen, onClick: { focused = true },
                            onFirstDraw: { toolbarReady = true; model.firstImageDrawn() },
                            onCommit: model.imageCommitted)
                    .contextMenu { ImageContextMenu(model: model) }
            } else if let message = model.errorMessage {
                Text(message).messageBox()
            } else if let folder = model.emptyFolder {
                Text("No images in \(folder.lastPathComponent)").messageBox()
            } else if !model.isOpening && model.list.current == nil {
                // Only when nothing is on its way: a loading image shows black, not the hint.
                Text("Open an image with ⌘O, or drop one here").messageBox()
            }
        }
        .overlay {
            if model.chooser != nil { FolderChooserView(model: model) }
            if let operation = model.destinationPanel { DestinationPanel(model: model, operation: operation) }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil {
                Text(message)
                    .messageBox()
                    .padding()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if model.isFullScreen, showOverlay, let url = model.list.current {
                Text(OverlayTemplate.render(overlayTemplate, values: overlayValues(url)))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
                    .padding()
            }
        }
        // Not onGeometryChange: it misses the restored window frame at launch, leaving fit at the 100×48 placeholder.
        // Inside the status bar's inset, so fit and its zoom % use the area above the bar.
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size, initial: true) { model.viewSize = geo.size }
        })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !statusBarHidden, !model.isFullScreen { StatusBar(model: model) }
        }
        // On a new image and on entering full screen (double-click, F or Return leave the image as is).
        .onChange(of: model.image) { hidePointerInFullScreen() }
        .onChange(of: model.isFullScreen) { hidePointerInFullScreen() }
        .modifier(ViewerToolbarPlacement(model: model, ready: toolbarReady))
        .onChange(of: model.image != nil || model.errorMessage != nil || model.emptyFolder != nil || !model.isOpening,
                  initial: true) { if $1, model.image == nil { ViewerModel.afterFrame { toolbarReady = true } } }
        .toolbar(toolbarHidden || hidesToolbarForFullScreen ? .hidden : .visible, for: .windowToolbar)
        .modifier(ToolbarHiddenInFullScreen())
        .onChange(of: displayScale, initial: true) { model.displayScale = displayScale }
        // Not set on the window directly: SwiftUI puts the scene's title back on its next update.
        .navigationTitle(model.title)
        .inspector(isPresented: $model.showInfo) {
            InfoPanel(url: model.list.current, revision: model.fileRevision)
        }
        .focusedSceneValue(\.viewer, model)
        .onChange(of: activeState, initial: true) {
            guard activeState == .key else { return }
            ViewerModel.lastActive.use(model)
            model.becameActive()
        }
        .background(WindowAccessor { window in
            model.window = window
            // A restored or reopened window may already be in full screen; no didEnter notification follows.
            model.isFullScreen = window.styleMask.contains(.fullScreen)
            if !rememberFrame, !model.isFullScreen { Self.place(window) }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = false }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: focused, initial: true) { model.hasKeyboardFocus = focused }
        .onAppear {
            focused = true
            ViewerModel.windows.viewerOpened()
        }
        .onDisappear { ViewerModel.windows.viewerClosed() }
        .onKeyPress(action: handle)
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Fit shrinks large images to the view; a zoom factor scales the file's full pixel size, so a smaller
    /// decode shown while the full one loads already has its final size (never another file's size).
    private func drawSize(_ image: CGImage) -> CGSize {
        let factor: Double? = if case .factor(let factor) = model.zoom { factor } else { nil }
        return ZoomSteps.drawSize(decoded: CGSize(width: image.width, height: image.height), full: fullSize,
                                  factor: factor, view: model.viewSize, displayScale: displayScale)
    }

    /// The file's pixel size, for the current file and page only (never another file's size).
    private var fullSize: CGSize? {
        let info = model.fileInfo
        return info?.isFor(model.list.current, page: model.page) == true ? info?.pixelSize : nil
    }

    /// The pixels `image` stands for, so a smaller decode is smoothed or not as the full one will be.
    private func pixelSize(_ image: CGImage) -> CGSize {
        ZoomSteps.pixelSize(decoded: CGSize(width: image.width, height: image.height), full: fullSize)
    }

    /// shortcut: macOS 14 has no `windowToolbarFullScreenVisibility`, so it still hides the toolbar mid-transition
    /// (the content can stay at the window's old size), drop when macOS 15 is the minimum.
    private var hidesToolbarForFullScreen: Bool {
        if #available(macOS 15, *) { false } else { model.isFullScreen }
    }

    private func hidePointerInFullScreen() {
        if model.isFullScreen, hidePointer { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    private func overlayValues(_ url: URL) -> [String: String] {
        var values = ["name": url.lastPathComponent,
                      "folder": url.deletingLastPathComponent().lastPathComponent,
                      "index": "\(model.list.index + 1)", "count": "\(model.list.urls.count)"]
        if let file = model.fileValues, file.url == url { values.merge(file.values) { $1 } }
        return values
    }

    /// Viewer shortcuts live here, not in the menus: a menu shortcut would also fire while typing
    /// in the Batch window's text fields (⌘⌫ there means "delete to start of line").
    /// The Mac's ⌫ key sends U+007F; SwiftUI's `.delete` is U+0008 and never matches it.
    private static let backspace = KeyEquivalent("\u{7F}")
    private static let f7 = KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!))
    private static let f8 = KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey)!))

    /// Where the next window goes when frames aren't remembered: the first is centred, the rest cascade from it.
    private static var cascadePoint: NSPoint?

    private static func place(_ window: NSWindow) {
        window.setContentSize(NSSize(width: 960, height: 640))
        if let point = cascadePoint {
            cascadePoint = window.cascadeTopLeft(from: point)
        } else {
            window.center()
            cascadePoint = window.cascadeTopLeft(from: .zero)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Arrow keys carry the numeric-pad/function flags and Caps Lock changes nothing here,
        // so only these modifiers count.
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        if model.isChooserOpen { return handleChooser(press, modifiers) }
        if let operation = model.destinationPanel { return handleDestinations(press, modifiers, operation) }
        if modifiers == .option {
            switch press.key {
            case .rightArrow: model.nextPage(); return .handled
            case .leftArrow: model.previousPage(); return .handled
            default: return .ignored
            }
        }
        if modifiers == .command, press.key == Self.backspace {
            model.moveCurrentToTrash()
            return .handled
        }
        if modifiers.isEmpty {
            switch press.key {
            case .rightArrow: if !panController.pan(dx: 1, dy: 0) { model.next() }; return .handled
            case .leftArrow: if !panController.pan(dx: -1, dy: 0) { model.previous() }; return .handled
            case .downArrow: if !panController.pan(dx: 0, dy: 1) { model.next() }; return .handled
            case .upArrow: if !panController.pan(dx: 0, dy: -1) { model.previous() }; return .handled
            case .space, .pageDown: model.next(); return .handled
            case Self.backspace, .pageUp: model.previous(); return .handled
            case .home: model.first(); return .handled
            case .end: model.last(); return .handled
            case .deleteForward: model.moveCurrentToTrash(); return .handled
            case Self.f7: model.showDestinations(.move); return .handled
            case Self.f8: model.showDestinations(.copy); return .handled
            case .return: model.toggleFullScreen(); return .handled
            case .escape:
                guard model.isFullScreen else { return .ignored }
                model.toggleFullScreen()
                return .handled
            default: break
            }
        }
        // Shift may be needed to type a character key ('+' on US, digits on AZERTY).
        guard modifiers.subtracting(.shift).isEmpty,
              let action = ViewerKey.action(characters: press.characters, shift: modifiers.contains(.shift))
        else { return .ignored }
        switch action {
        case .rotateRight: model.rotate(.clockwise)
        case .rotateLeft: model.rotate(.counterClockwise)
        case .toggleInfo: model.showInfo.toggle()
        case .toggleFullScreen: model.toggleFullScreen()
        case .fit: model.setZoom(.fit)
        case .actualSize: model.setZoom(.factor(1))
        case .zoomIn: model.zoomIn()
        case .zoomOut: model.zoomOut()
        case .open: model.showOpenPanel()
        case .batch: openWindow(id: "batch")
        case .minimize: model.window?.miniaturize(nil)
        case .settings: SettingsWindow.show()
        case .about: openWindow(id: "about")
        case .saveAs: model.saveAs()
        }
        return .handled
    }

    /// While the folder chooser shows, keys drive it and nothing else.
    private func handleChooser(_ press: KeyPress, _ modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isEmpty else { return .handled }
        switch press.key {
        case .upArrow: model.chooserMove(-1)
        case .downArrow: model.chooserMove(1)
        case .rightArrow, .space: model.chooserEnter()
        case .leftArrow: model.chooserUp()
        case .return: model.chooserOpen()
        case .escape: model.closeChooser()
        default: break
        }
        return .handled
    }

    /// While the F7 / F8 panel shows: a slot key picks a folder, ↑ ↓ and Return use the highlight.
    private func handleDestinations(_ press: KeyPress, _ modifiers: EventModifiers,
                                    _ operation: FileOperation) -> KeyPress.Result {
        guard modifiers.subtracting(.shift).isEmpty else { return .handled }
        switch press.key {
        case .escape: model.destinationPanel = nil
        case .upArrow: model.slots.lastUsed = max(model.slots.lastUsed - 1, 0)
        case .downArrow: model.slots.lastUsed = min(model.slots.lastUsed + 1, DestinationSlots.count - 1)
        case .return: pick(model.slots.lastUsed)
        default:
            if let character = press.characters.first, let slot = DestinationSlots.slot(forKey: character) {
                pick(slot)
            }
        }
        return .handled
    }

    /// An empty slot asks for its folder first.
    private func pick(_ slot: Int) {
        if model.slots[slot] == nil, !model.chooseFolder(for: slot) { return }
        model.transfer(to: slot)
    }
}

struct ImageContextMenu: View {
    let model: ViewerModel

    var body: some View {
        Button("Copy") { model.copyImage() }
        Divider()
        Button("Rotate Left") { model.rotate(.counterClockwise) }
        Button("Rotate Right") { model.rotate(.clockwise) }
        Divider()
        Button("Move to Folder…") { model.showDestinations(.move) }
        Button("Copy to Folder…") { model.showDestinations(.copy) }
        Button("Move to Trash") { model.moveCurrentToTrash() }
        Divider()
        Button("Show in Finder") { model.showInFinder() }
        OpenWithMenu(model: model)
    }
}

/// The apps set in Settings › Open With, by name.
struct OpenWithMenu: View {
    let model: ViewerModel?
    // Observed, so the menu follows Settings › Open With at once.
    @AppStorage(AppSettings.openWith[0].key) private var app1 = ""
    @AppStorage(AppSettings.openWith[1].key) private var app2 = ""
    @AppStorage(AppSettings.openWith[2].key) private var app3 = ""

    var body: some View {
        Menu("Open With") {
            ForEach(0..<3, id: \.self) { index in
                let path = [app1, app2, app3][index]
                Button(path.isEmpty ? String(localized: "App \(index + 1) not set") : FileManager.default.displayName(atPath: path)) {
                    model?.openWith(index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                .disabled(path.isEmpty || model?.availability.hasCurrent != true)
            }
        }
    }
}

/// Reports the hosting window once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension FocusedValues {
    /// The viewer of the focused window; menu commands act on it.
    @Entry var viewer: ViewerModel?
}

struct InfoPanel: View {
    let url: URL?
    /// Changes when the file is rewritten (rotation), so the fields are read again.
    let revision: Int
    @State private var fields: [MetadataField] = []

    var body: some View {
        Form {
            ForEach(fields, id: \.label) { field in
                LabeledContent(field.label, value: field.value)
            }
        }
        // Reads the file off the main thread.
        .task(id: "\(revision) \(url?.path ?? "")") {
            guard let url else { return fields = [] }
            let read = await Task.detached { MetadataReader.fields(for: url) }.value
            if !Task.isCancelled { fields = read }
        }
        .textSelection(.enabled)
        .inspectorColumnWidth(min: 220, ideal: 260)
    }
}

/// Whether viewer windows hide their toolbar (View › Hide Toolbar).
private let toolbarHiddenKey = "toolbarHidden"
/// Whether viewer windows hide their status bar (View › Hide Status Bar).
private let statusBarHiddenKey = "statusBarHidden"

/// Only the main window's toolbar is customizable. AppKit copies every item inserted into a customizable
/// toolbar into all windows with that toolbar's id, so a second window adding its buttons after its first
/// image (or page buttons for a PDF) crashed with "already contains an item". Extra windows show the same
/// buttons at once instead (the main window waits for the launch budget, see `toolbarReady`).
private struct ViewerToolbarPlacement: ViewModifier {
    let model: ViewerModel
    let ready: Bool

    func body(content: Content) -> some View {
        if model === ViewerModel.main {
            content.toolbar(id: "viewer") { ViewerToolbar(model: model, ready: ready) }
        } else {
            content.toolbar { ViewerToolbar(model: model, ready: true) }
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(toolbarHiddenKey) private var toolbarHidden = false
    @AppStorage(statusBarHiddenKey) private var statusBarHidden = false

    var body: some Commands {
        // Built at launch even when no window is restored (the last one was closed or minimized): a file
        // opened from Finder then still gets the main window, which otherwise waited for a window's view.
        let _ = OpensViewerWindows.install(openWindow)
        CommandGroup(replacing: .appInfo) {
            Button("About Featherview  (A)") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.show() }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…  (O)") { (model ?? ViewerModel.lastActive.current).showOpenPanel() }
                .keyboardShortcut("o")
        }
        // Not replacing .saveItem: SwiftUI shows nothing in that group for an app without documents.
        CommandGroup(after: .newItem) {
            Button("Save As…  (S)") { model?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model?.availability.canChangeFile != true)
        }
        CommandGroup(replacing: .pasteboard) {
            // Text fields and selected text (batch window, Info panel) keep their own Copy and Paste.
            Button("Copy") {
                // Selected text in the Info panel isn't an NSText, but it takes SwiftUI focus from the viewer.
                if let model, model.hasKeyboardFocus, !(NSApp.keyWindow?.firstResponder is NSText) {
                    model.copyImage()
                } else {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("c")
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a")
        }
        CommandMenu("Image") {
            // Disabled as the toolbar buttons are, so menu and toolbar agree.
            Group {
                Button("Next  (→ or Space)") { model?.next() }
                Button("Previous  (← or ⌫)") { model?.previous() }
            }
            .disabled(model?.availability.canBrowse != true)
            Group {
                Button("Next Page  (⌥→)") { model?.nextPage() }
                Button("Previous Page  (⌥←)") { model?.previousPage() }
            }
            .disabled(model?.availability.hasPages != true)
            Divider()
            Group {
                Button("Rotate Right  (R)") { model?.rotate(.clockwise) }
                Button("Rotate Left  (L)") { model?.rotate(.counterClockwise) }
                Divider()
                // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
                Button("Move to Folder…  (F7)") { model?.showDestinations(.move) }
                Button("Copy to Folder…  (F8)") { model?.showDestinations(.copy) }
                Button("Move to Trash  (⌘⌫ or ⌦)") { model?.moveCurrentToTrash() }
            }
            .disabled(model?.availability.canChangeFile != true)
            Button("Show in Finder") { model?.showInFinder() }
                .disabled(model?.availability.hasCurrent != true)
            OpenWithMenu(model: model)
            Button("Show Info  (I)") { model?.showInfo.toggle() }
                .disabled(model?.availability.hasCurrent != true)
            Divider()
            Button("Batch Convert…  (B)") { openWindow(id: "batch") }
                .keyboardShortcut("b")
        }
        // Not ToolbarCommands: SwiftUI shows its toolbar at every launch, so whether it's hidden is kept here.
        CommandGroup(replacing: .toolbar) {
            Button(toolbarHidden ? "Show Toolbar" : "Hide Toolbar") { toolbarHidden.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Customize Toolbar…") {
                NSApp.sendAction(#selector(NSWindow.runToolbarCustomizationPalette(_:)), to: nil, from: nil)
            }
            .disabled(model == nil || toolbarHidden)
            Button(statusBarHidden ? "Show Status Bar" : "Hide Status Bar") { statusBarHidden.toggle() }
        }
        CommandGroup(after: .toolbar) {
            Group {
                Button("Zoom to Fit  (0)") { model?.setZoom(.fit) }
                Button("Actual Size  (1)") { model?.setZoom(.factor(1)) }
                Button("Zoom In  (+)") { model?.zoomIn() }
                Button("Zoom Out  (−)") { model?.zoomOut() }
            }
            .disabled(model?.availability.hasCurrent != true)
        }
    }
}

private extension View {
    /// Readable on any background colour the user picks (grey text vanishes on black).
    func messageBox() -> some View {
        padding(8).panelBackground(cornerRadius: 6)
    }
}

extension View {
    /// Liquid Glass on macOS 26+ (spec "Viewer"); the material before.
    @ViewBuilder func panelBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// Full screen hides the toolbar the native way: it slides in with the menu bar when the pointer is at the top.
/// Hiding it with `.toolbar(.hidden)` from willEnterFullScreen left the content at the old window size (View menu)
/// or kept the toolbar's strip as a black band (Return).
struct ToolbarHiddenInFullScreen: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.windowToolbarFullScreenVisibility(.onHover) } else { content }
    }
}
