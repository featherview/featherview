import AppKit
import FeatherviewCore
import SwiftUI

/// The standard Mac toolbar (spec "Toolbar"): each button does what its key does; the tooltip names the key.
/// Customizable, so View › Customize Toolbar… and Hide Toolbar work as in any Mac app.
/// The content reads only `pageCount` and `isAnimation` (which change only between kinds of files): reading
/// anything that changes per image would rebuild every item on each swap (budget 16 ms).
struct ViewerToolbar: CustomizableToolbarContent {
    let model: ViewerModel
    /// False until the first image (or message) shows; see ViewerView.toolbarReady. Gates the trailing buttons.
    let ready: Bool

    @ViewBuilder private var previous: some View {
        if ready {
            ToolbarButton("Previous", "chevron.backward", "Previous image (←)", enabled: { $0.availability.canGoBack }, model) { $0.previous() }
        } else {
            Color.clear.frame(width: Theme.backForwardWidth, height: 1)
        }
    }

    var body: some CustomizableToolbarContent {
        // The title is there from the first frame; until the buttons are built (they cost ~20 ms at launch) a blank
        // item without glass holds the back / forward capsule's place, so the title never moves.
        if #available(macOS 26, *) {
            ToolbarItem(id: "previous", placement: .navigation) { previous }
                .sharedBackgroundVisibility(ready ? .automatic : .hidden)
        } else {
            ToolbarItem(id: "previous", placement: .navigation) { previous }
        }
        if ready {
            ToolbarItem(id: "next", placement: .navigation) {
                ToolbarButton("Next", "chevron.forward", "Next image (→)", enabled: { $0.availability.canGoForward }, model) { $0.next() }
            }
        }
        // The title after back / forward: the name in the title font, the counter quieter (docs/DESIGN.md
        // "Typography"). The window's own title is hidden (ViewerView.matchTitle).
        if #available(macOS 26, *) {
            // Text, not a control: no glass behind it.
            ToolbarItem(id: "title", placement: .navigation) { WindowTitle(model: model) }
                .customizationBehavior(.disabled)
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "title", placement: .navigation) { WindowTitle(model: model) }
                .customizationBehavior(.disabled)
        }
        // The window's own title, which took the space between, is removed: a flexible space pushes the rest
        // to the trailing edge.
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        if ready {
            if model.pageCount > 1 || model.isAnimation {
                ToolbarItem(id: "previousPage", placement: .primaryAction) {
                    ToolbarButton("Previous Page", "arrow.up.doc",
                                  model.isAnimation ? "Previous frame (⌥←)" : "Previous page (⌥←)",
                                  enabled: { $0.availability.hasPages }, model) { $0.previousPage() }
                }
                ToolbarItem(id: "nextPage", placement: .primaryAction) {
                    ToolbarButton("Next Page", "arrow.down.doc", model.isAnimation ? "Next frame (⌥→)" : "Next page (⌥→)",
                                  enabled: { $0.availability.hasPages }, model) { $0.nextPage() }
                }
            }
            ToolbarItem(id: "thumbnails", placement: .primaryAction) {
                ThumbnailsToggle(model: model)
            }
            ToolbarItem(id: "rotateLeft", placement: .primaryAction) {
                ToolbarButton("Rotate Left", "rotate.left", "Rotate left (L)", enabled: { $0.availability.canChangeFile }, model) { $0.rotate(.counterClockwise) }
            }
            ToolbarItem(id: "rotateRight", placement: .primaryAction) {
                ToolbarButton("Rotate Right", "rotate.right", "Rotate right (R)", enabled: { $0.availability.canChangeFile }, model) { $0.rotate(.clockwise) }
            }
            ToolbarItem(id: "flipHorizontal", placement: .primaryAction) {
                ToolbarButton("Flip Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip horizontal (H)",
                              enabled: { $0.availability.canChangeFile }, model) { $0.flip(.horizontal) }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "flipVertical", placement: .primaryAction) {
                ToolbarButton("Flip Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip vertical (V)",
                              enabled: { $0.availability.canChangeFile }, model) { $0.flip(.vertical) }
            }
            .defaultCustomization(.hidden)
        }
        // Two blocks: Swift 6.3 (CI) takes at most 10 items in one.
        if ready {
            ToolbarItem(id: "zoomOut", placement: .primaryAction) {
                ToolbarButton("Zoom Out", "minus.magnifyingglass", "Zoom out (−)", enabled: { $0.availability.canZoom }, model) { $0.zoomOut() }
            }
            ToolbarItem(id: "fit", placement: .primaryAction) {
                ToolbarButton("Zoom to Fit", "arrow.up.left.and.down.right.magnifyingglass", "Zoom to fit (0)",
                              enabled: { $0.availability.canZoom }, model) { $0.setFitMode(.fit) }
            }
            ToolbarItem(id: "zoomIn", placement: .primaryAction) {
                ToolbarButton("Zoom In", "plus.magnifyingglass", "Zoom in (+)", enabled: { $0.availability.canZoom }, model) { $0.zoomIn() }
            }
            ToolbarItem(id: "zoomToWidth", placement: .primaryAction) {
                ToolbarButton("Zoom to Width", "arrow.left.and.right", "Zoom to width (2)",
                              enabled: { $0.availability.canZoom }, model) { $0.setFitMode(.width) }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "zoomToHeight", placement: .primaryAction) {
                ToolbarButton("Zoom to Height", "arrow.up.and.down", "Zoom to height (3)",
                              enabled: { $0.availability.canZoom }, model) { $0.setFitMode(.height) }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "keepZoom", placement: .primaryAction) {
                KeepZoomToggle(model: model)
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "info", placement: .primaryAction) {
                InfoToggle(model: model)
            }
            ToolbarItem(id: "share", placement: .primaryAction) {
                ShareButton(model: model)
            }
            ToolbarItem(id: "trash", placement: .primaryAction) {
                ToolbarButton("Move to Trash", "trash", "Move to Trash (⌘⌫)", enabled: { $0.availability.canChangeFile }, model) { $0.moveCurrentToTrash() }
            }
        }
    }
}

/// A toolbar symbol from an NSImage made once: SwiftUI looks a named symbol up in the asset catalog again each time
/// its item changes (~18 ms when T enables or disables most items).
@MainActor private enum ToolbarSymbol {
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> Image {
        if let image = images[name] { return Image(nsImage: image) }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        images[name] = image
        return Image(nsImage: image)
    }
}

/// One button; its own view, so only it re-evaluates when whether it can act changes.
private struct ToolbarButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let help: LocalizedStringKey
    let enabled: (ViewerModel) -> Bool
    let model: ViewerModel
    let action: (ViewerModel) -> Void

    init(_ title: LocalizedStringKey, _ symbol: String, _ help: LocalizedStringKey, enabled: @escaping (ViewerModel) -> Bool,
         _ model: ViewerModel, action: @escaping (ViewerModel) -> Void) {
        self.title = title
        self.symbol = symbol
        self.help = help
        self.enabled = enabled
        self.model = model
        self.action = action
    }

    var body: some View {
        Button { action(model) } label: { Label { Text(title) } icon: { ToolbarSymbol.image(symbol) } }
            .help(help)
            .disabled(!enabled(model))
    }
}

/// Info: toggled on while the panel shows.
private struct InfoToggle: View {
    @Bindable var model: ViewerModel

    var body: some View {
        Toggle(isOn: $model.showInfo) { Label { Text("Info") } icon: { ToolbarSymbol.image("info.circle") } }
            .help("Show info (I)")
            .disabled(!model.availability.canShowInfo)
    }
}

/// Keep Zoom: on while a new image keeps the zoom and scroll position of the one before.
private struct KeepZoomToggle: View {
    let model: ViewerModel
    @AppStorage(AppSettings.keepZoom.key) private var keepZoom = AppSettings.keepZoom.defaultValue

    var body: some View {
        Toggle(isOn: $keepZoom) { Label { Text("Keep Zoom") } icon: { ToolbarSymbol.image("pin") } }
            .help("Keep zoom (⇧L)")
    }
}

/// Share: the system share picker for the current file.
private struct ShareButton: View {
    let model: ViewerModel
    @State private var anchor = Anchor()

    var body: some View {
        // Not ShareLink: its item changes with every image, and SwiftUI rebuilds the whole toolbar for that
        // (~12 ms of each swap). The file is read when the button is clicked.
        Button {
            guard let url = model.list.current, let view = anchor.view else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } label: { Label { Text("Share") } icon: { ToolbarSymbol.image("square.and.arrow.up") } }
        .help("Share")
        .disabled(!model.availability.canChangeFile)
        .background(AnchorView(anchor: anchor))
    }

    /// The button's view, for the picker to point at.
    final class Anchor { weak var view: NSView? }

    private struct AnchorView: NSViewRepresentable {
        let anchor: Anchor
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
    }
}

/// Thumbnails: toggled on while the grid shows (Decision 1).
private struct ThumbnailsToggle: View {
    let model: ViewerModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.isGrid }, set: { _ in model.toggleGrid() })) {
            Label { Text("Thumbnails") } icon: { ToolbarSymbol.image("square.grid.2x2") }
        }
            .help("Thumbnails (T)")
            .disabled(!model.availability.canShowGrid)
    }
}

/// The name being renamed; its draft lives here, made when renaming starts.
private struct TitleRenameField: View {
    let model: ViewerModel
    @State private var draft: String

    init(model: ViewerModel) {
        self.model = model
        _draft = State(initialValue: model.renamingURL?.lastPathComponent ?? "")
    }

    var body: some View {
        RenameField(text: $draft, onCommit: { await model.commitRename(draft) }, onCancel: model.cancelRename)
    }
}

/// The file name, then " — n / N" in the secondary colour with tabular digits; the name truncates first.
private struct WindowTitle: View {
    let model: ViewerModel

    var body: some View {
        HStack(spacing: Theme.titleGap) {
            if model.renaming && !model.renamingInSheet {
                TitleRenameField(model: model)
            } else {
                Text(verbatim: model.titleName)
                    .font(Theme.windowTitle)
                    .foregroundStyle(Theme.labelPrimary)
                    .truncationMode(.tail)
                    // A click on the name renames, as in Preview.
                    .overlay { TitleDrag(onClick: model.beginRename) }
            }
            if let counter = model.titleCounter {
                Text(verbatim: counter)
                    .font(Theme.counter)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize()
                    .overlay { TitleDrag() }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The title moves the window when dragged, as any title does; SwiftUI views in the toolbar keep the mouse otherwise.
private struct TitleDrag: NSViewRepresentable {
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onClick = onClick }

    final class DragView: NSView {
        var onClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = event.locationInWindow
            while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                if next.type == .leftMouseUp { return onClick?() ?? () }
                if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                    return window.performDrag(with: event)
                }
            }
        }
    }
}
