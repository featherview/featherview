import FeatherviewCore
import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = model.image {
                canvas(image)
            } else {
                Text(model.errorMessage ?? "Open an image with ⌘O, or drop one here")
                    .foregroundStyle(.secondary)
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
            model.revealWindow = { [openWindow] in openWindow(id: "viewer") }
        }
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
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Arrow keys carry the numeric-pad/function flags and Caps Lock changes nothing here,
        // so only these modifiers count.
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        if modifiers == .command, press.key == .delete {
            model.moveCurrentToTrash()
            return .handled
        }
        guard modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .rightArrow, .space, .pageDown, .downArrow: model.next()
        case .leftArrow, .delete, .pageUp, .upArrow: model.previous()
        case .home: model.first()
        case .end: model.last()
        case .escape:
            guard model.isFullScreen else { return .ignored }
            model.toggleFullScreen()
        default:
            switch press.characters.lowercased() {
            case "r": model.rotate(.clockwise)
            case "l": model.rotate(.counterClockwise)
            case "i": model.showInfo.toggle()
            case "f": model.toggleFullScreen()
            case "0": model.setZoom(.fit)
            case "1": model.setZoom(.factor(1))
            case "+", "=": model.zoomIn()
            case "-": model.zoomOut()
            default: return .ignored
            }
        }
        return .handled
    }
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
    let model: ViewerModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.showOpenPanel() }
                .keyboardShortcut("o")
        }
        CommandMenu("Image") {
            Button("Next  (→ or Space)") { model.next() }
            Button("Previous  (← or ⌫)") { model.previous() }
            Divider()
            Button("Rotate Right  (R)") { model.rotate(.clockwise) }
            Button("Rotate Left  (L)") { model.rotate(.counterClockwise) }
            Divider()
            // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
            Button("Move to Trash  (⌘⌫)") { model.moveCurrentToTrash() }
            Button("Show Info  (I)") { model.showInfo.toggle() }
            Divider()
            Button("Batch Convert…") { openWindow(id: "batch") }
                .keyboardShortcut("b")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom to Fit  (0)") { model.setZoom(.fit) }
            Button("Actual Size  (1)") { model.setZoom(.factor(1)) }
            Button("Zoom In  (+)") { model.zoomIn() }
            Button("Zoom Out  (−)") { model.zoomOut() }
        }
    }
}
