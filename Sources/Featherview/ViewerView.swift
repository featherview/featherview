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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = model.image {
                canvas(image)
            } else if let message = model.errorMessage {
                Text(message).foregroundStyle(.secondary)
            } else if !model.isOpening && model.list.current == nil {
                // Only when nothing is on its way: a loading image shows black, not the hint.
                Text("Open an image with ⌘O, or drop one here").foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil {
                Text(message)
                    .padding(8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 6))
                    .padding()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.viewSize = $0 }
        .onChange(of: displayScale, initial: true) { model.displayScale = displayScale }
        .navigationTitle(model.title)
        .inspector(isPresented: $model.showInfo) {
            InfoPanel(url: model.list.current, revision: model.fileRevision)
        }
        .focusedSceneValue(\.viewer, model)
        .onChange(of: activeState, initial: true) { if activeState == .key { ViewerModel.lastActive.use(model) } }
        .background(WindowAccessor { window in
            model.window = window
            // A restored or reopened window may already be in full screen; no didEnter notification follows.
            model.isFullScreen = window.styleMask.contains(.fullScreen)
            if !rememberFrame { window.setContentSize(NSSize(width: 960, height: 640)); window.center() }
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

    @ViewBuilder
    private func canvas(_ image: CGImage) -> some View {
        let pointSize = CGSize(width: CGFloat(image.width) / displayScale,
                               height: CGFloat(image.height) / displayScale)
        switch model.zoom {
        case .fit:
            // Shrinks large images to the window; small ones stay at their real size.
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: pointSize.width, maxHeight: pointSize.height)
        case .factor(let factor):
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(factor >= 2 ? .none : .high)
                    .frame(width: pointSize.width * factor, height: pointSize.height * factor)
            }
        }
    }

    /// Viewer shortcuts live here, not in the menus: a menu shortcut would also fire while typing
    /// in the Batch window's text fields (⌘⌫ there means "delete to start of line").
    /// The Mac's ⌫ key sends U+007F; SwiftUI's `.delete` is U+0008 and never matches it.
    private static let backspace = KeyEquivalent("\u{7F}")

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Arrow keys carry the numeric-pad/function flags and Caps Lock changes nothing here,
        // so only these modifiers count.
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        if modifiers == .command, press.key == Self.backspace {
            model.moveCurrentToTrash()
            return .handled
        }
        if modifiers.isEmpty, press.key == .deleteForward {
            model.moveCurrentToTrash()
            return .handled
        }
        if modifiers.isEmpty {
            switch press.key {
            case .rightArrow, .space, .pageDown, .downArrow: model.next(); return .handled
            case .leftArrow, Self.backspace, .pageUp, .upArrow: model.previous(); return .handled
            case .home: model.first(); return .handled
            case .end: model.last(); return .handled
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
