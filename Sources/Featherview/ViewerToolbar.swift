import SwiftUI

/// The standard Mac toolbar (spec "Toolbar"): each button does what its key does; the tooltip names the key.
/// Customizable, so View › Customize Toolbar… and Hide Toolbar work as in any Mac app.
/// The content reads only `pageCount` (which changes only between single- and multi-page files): reading
/// anything that changes per image would rebuild every item on each swap (budget 16 ms).
struct ViewerToolbar: CustomizableToolbarContent {
    let model: ViewerModel
    /// False until the first image (or message) shows; see ViewerView.toolbarReady.
    let ready: Bool

    var body: some CustomizableToolbarContent {
        // Always one item, a blank one until ready: with none the window starts with a plain title bar,
        // which then grows and moves the image when the buttons arrive.
        ToolbarItem(id: "previous", placement: .navigation) {
            if ready {
                ToolbarButton("Previous", "chevron.backward", "Previous image (←)", enabled: { $0.availability.canBrowse }, model) { $0.previous() }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        if ready {
            ToolbarItem(id: "next", placement: .navigation) {
                ToolbarButton("Next", "chevron.forward", "Next image (→)", enabled: { $0.availability.canBrowse }, model) { $0.next() }
            }
            if model.pageCount > 1 {
                ToolbarItem(id: "previousPage") {
                    ToolbarButton("Previous Page", "arrow.up.doc", "Previous page (⌥←)", enabled: { $0.availability.hasPages }, model) { $0.previousPage() }
                }
                ToolbarItem(id: "nextPage") {
                    ToolbarButton("Next Page", "arrow.down.doc", "Next page (⌥→)", enabled: { $0.availability.hasPages }, model) { $0.nextPage() }
                }
            }
            ToolbarItem(id: "rotateLeft") {
                ToolbarButton("Rotate Left", "rotate.left", "Rotate left (L)", enabled: { $0.availability.canChangeFile }, model) { $0.rotate(.counterClockwise) }
            }
            ToolbarItem(id: "rotateRight") {
                ToolbarButton("Rotate Right", "rotate.right", "Rotate right (R)", enabled: { $0.availability.canChangeFile }, model) { $0.rotate(.clockwise) }
            }
            ToolbarItem(id: "zoomOut") {
                ToolbarButton("Zoom Out", "minus.magnifyingglass", "Zoom out (−)", enabled: { $0.availability.hasCurrent }, model) { $0.zoomOut() }
            }
            ToolbarItem(id: "fit") {
                ToolbarButton("Zoom to Fit", "arrow.up.left.and.down.right.magnifyingglass", "Zoom to fit (0)",
                              enabled: { $0.availability.hasCurrent }, model) { $0.setZoom(.fit) }
            }
            ToolbarItem(id: "zoomIn") {
                ToolbarButton("Zoom In", "plus.magnifyingglass", "Zoom in (+)", enabled: { $0.availability.hasCurrent }, model) { $0.zoomIn() }
            }
            ToolbarItem(id: "info") {
                ToolbarButton("Info", "info.circle", "Show info (I)", enabled: { $0.availability.hasCurrent }, model) { $0.showInfo.toggle() }
            }
            ToolbarItem(id: "trash") {
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
