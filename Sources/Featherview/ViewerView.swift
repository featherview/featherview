import FeatherviewCore
import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @FocusState private var focused: Bool
    @Environment(\.controlActiveState) private var activeState
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @State private var panController = PanController()
    @AppStorage(AppSettings.backgroundColor.key) private var backgroundHex = AppSettings.backgroundColor.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var overlayTemplate = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue

    private var background: Color { Color(nsColor: backgroundNSColor) }
    private var backgroundNSColor: NSColor {
        guard let c = HexColor.parse(backgroundHex) else { return .black }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if let image = model.image {
                ImageCanvas(image: image, size: drawSize(image), displayScale: displayScale, background: backgroundNSColor,
                            checkerboard: checkerboard, panController: panController,
                            onDoubleClick: model.toggleFullScreen)
            } else if let message = model.errorMessage {
                Text(message).foregroundStyle(.secondary)
            } else if let folder = model.emptyFolder {
                Text("No images in \(folder.lastPathComponent)").foregroundStyle(.secondary)
            } else if !model.isOpening && model.list.current == nil {
                // Only when nothing is on its way: a loading image shows black, not the hint.
                Text("Open an image with ⌘O, or drop one here").foregroundStyle(.secondary)
            }
        }
        .overlay {
            if model.chooser != nil { FolderChooserView(model: model) }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil {
                Text(message)
                    .padding(8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 6))
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
        // On a new image and on entering full screen (double-click, F or Return leave the image as is).
        .onChange(of: model.image) { hidePointerInFullScreen() }
        .onChange(of: model.isFullScreen) { hidePointerInFullScreen() }
        .toolbar(model.isFullScreen ? .hidden : .automatic, for: .windowToolbar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.viewSize = $0 }
        .onChange(of: displayScale, initial: true) { model.displayScale = displayScale }
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
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
        .onAppear {
            focused = true
            ViewerModel.windows.viewerOpened()
        }
        .onDisappear { ViewerModel.windows.viewerClosed() }
        .onKeyPress(action: handle)
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Fit shrinks large images to the view and never enlarges small ones; a zoom factor scales the full-size decode.
    private func drawSize(_ image: CGImage) -> CGSize {
        let points = CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
        switch model.zoom {
        case .fit:
            let scale = min(1, model.viewSize.width / max(points.width, 1), model.viewSize.height / max(points.height, 1))
            return CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
        case .factor(let factor):
            return CGSize(width: points.width * factor, height: points.height * factor)
        }
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
        case .settings: openSettings()
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

struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…  (O)") { (model ?? ViewerModel.lastActive.current).showOpenPanel() }
                .keyboardShortcut("o")
        }
        CommandMenu("Image") {
            Button("Next  (→ or Space)") { model?.next() }
            Button("Previous  (← or ⌫)") { model?.previous() }
            Button("Next Page  (⌥→)") { model?.nextPage() }
                .disabled((model?.pageCount ?? 1) < 2)
            Button("Previous Page  (⌥←)") { model?.previousPage() }
                .disabled((model?.pageCount ?? 1) < 2)
            Divider()
            Button("Rotate Right  (R)") { model?.rotate(.clockwise) }
            Button("Rotate Left  (L)") { model?.rotate(.counterClockwise) }
            Divider()
            // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
            Button("Move to Trash  (⌘⌫ or ⌦)") { model?.moveCurrentToTrash() }
            Button("Show Info  (I)") { model?.showInfo.toggle() }
            Divider()
            Button("Batch Convert…  (B)") { openWindow(id: "batch") }
                .keyboardShortcut("b")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom to Fit  (0)") { model?.setZoom(.fit) }
            Button("Actual Size  (1)") { model?.setZoom(.factor(1)) }
            Button("Zoom In  (+)") { model?.zoomIn() }
            Button("Zoom Out  (−)") { model?.zoomOut() }
        }
    }
}
