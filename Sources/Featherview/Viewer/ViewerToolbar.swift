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
            ToolbarItem(id: "zoomOut", placement: .primaryAction) {
                ToolbarButton("Zoom Out", "minus.magnifyingglass", "Zoom out (−)", enabled: { $0.availability.hasPicture && !$0.isGrid }, model) { $0.zoomOut() }
            }
            ToolbarItem(id: "fit", placement: .primaryAction) {
                ToolbarButton("Zoom to Fit", "arrow.up.left.and.down.right.magnifyingglass", "Zoom to fit (0)",
                              enabled: { $0.availability.hasPicture && !$0.isGrid }, model) { $0.setZoom(.fit) }
            }
            ToolbarItem(id: "zoomIn", placement: .primaryAction) {
                ToolbarButton("Zoom In", "plus.magnifyingglass", "Zoom in (+)", enabled: { $0.availability.hasPicture && !$0.isGrid }, model) { $0.zoomIn() }
            }
            ToolbarItem(id: "info", placement: .primaryAction) {
                InfoToggle(model: model)
            }
            ToolbarItem(id: "trash", placement: .primaryAction) {
                ToolbarButton("Move to Trash", "trash", "Move to Trash (⌘⌫)", enabled: { $0.availability.canChangeFile }, model) { $0.moveCurrentToTrash() }
            }
        }
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
        Button(title, systemImage: symbol) { action(model) }
            .help(help)
            .disabled(!enabled(model))
    }
}

/// Info: toggled on while the panel shows.
private struct InfoToggle: View {
    @Bindable var model: ViewerModel

    var body: some View {
        Toggle("Info", systemImage: "info.circle", isOn: $model.showInfo)
            .help("Show info (I)")
            .disabled(!model.availability.hasCurrent || model.isGrid || model.compareSession != nil)
    }
}

/// Thumbnails: toggled on while the grid shows (Decision 1).
private struct ThumbnailsToggle: View {
    let model: ViewerModel

    var body: some View {
        Toggle("Thumbnails", systemImage: "square.grid.2x2", isOn: Binding(get: { model.isGrid }, set: { _ in model.toggleGrid() }))
            .help("Thumbnails (T)")
            .disabled(!model.availability.canShowGrid)
    }
}

/// The file name, then " — n / N" in the secondary colour with tabular digits; the name truncates first.
private struct WindowTitle: View {
    let model: ViewerModel

    var body: some View {
        HStack(spacing: Theme.titleGap) {
            Text(verbatim: model.titleName)
                .font(Theme.windowTitle)
                .foregroundStyle(Theme.labelPrimary)
                .truncationMode(.tail)
            if let counter = model.titleCounter {
                Text(verbatim: counter)
                    .font(Theme.counter)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
