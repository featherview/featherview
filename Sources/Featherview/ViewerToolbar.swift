import SwiftUI

/// The standard Mac toolbar (spec "Toolbar"): each button does what its key does; the tooltip names the key.
/// Customizable, so View › Customize Toolbar… and Hide Toolbar work as in any Mac app.
struct ViewerToolbar: CustomizableToolbarContent {
    let model: ViewerModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "previous", placement: .navigation) {
            Button("Previous", systemImage: "chevron.backward") { model.previous() }.help("Previous image (←)")
        }
        ToolbarItem(id: "next", placement: .navigation) {
            Button("Next", systemImage: "chevron.forward") { model.next() }.help("Next image (→)")
        }
        if model.pageCount > 1 {
            ToolbarItem(id: "previousPage") {
                Button("Previous Page", systemImage: "arrow.up.doc") { model.previousPage() }.help("Previous page (⌥←)")
            }
            ToolbarItem(id: "nextPage") {
                Button("Next Page", systemImage: "arrow.down.doc") { model.nextPage() }.help("Next page (⌥→)")
            }
        }
        ToolbarItem(id: "rotateLeft") {
            Button("Rotate Left", systemImage: "rotate.left") { model.rotate(.counterClockwise) }.help("Rotate left (L)")
        }
        ToolbarItem(id: "rotateRight") {
            Button("Rotate Right", systemImage: "rotate.right") { model.rotate(.clockwise) }.help("Rotate right (R)")
        }
        ToolbarItem(id: "zoomOut") {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { model.zoomOut() }.help("Zoom out (−)")
        }
        ToolbarItem(id: "fit") {
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { model.setZoom(.fit) }
                .help("Zoom to fit (0)")
        }
        ToolbarItem(id: "zoomIn") {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoomIn() }.help("Zoom in (+)")
        }
        ToolbarItem(id: "info") {
            Button("Info", systemImage: "info.circle") { model.showInfo.toggle() }.help("Show info (I)")
        }
        ToolbarItem(id: "trash") {
            Button("Move to Trash", systemImage: "trash") { model.moveCurrentToTrash() }.help("Move to Trash (⌘⌫)")
        }
    }
}
