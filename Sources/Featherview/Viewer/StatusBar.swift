import FeatherviewCore
import SwiftUI

/// One line along the bottom of the viewer (spec "Viewer"): pixel size, zoom, file size, position, page, date.
/// In the grid: the focused file's details or the selection's count, then the thumbnail size slider (Decision 12).
/// In compare, one per pane: the pane's file name and details; pane 2's adds Swap and Stop Comparing.
/// Its own view, so the values changing per image re-evaluate only this, not the window's toolbar.
struct StatusBar: View {
    let model: ViewerModel
    /// The compare pane this strip belongs to; nil for the window's one strip.
    var pane: CompareSession.Pane?
    @AppStorage(AppSettings.thumbnailSize.key) private var thumbnailSize = AppSettings.thumbnailSize.defaultValue

    var body: some View {
        HStack(spacing: Theme.stripGap) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 {
                    Theme.stripSeparator.frame(width: 1, height: Theme.stripSeparatorHeight)
                }
                Text(field)
            }
            if model.isGrid {
                Spacer(minLength: 0)
                Slider(value: $thumbnailSize, in: ThumbnailSize.range)
                    .controlSize(.mini)
                    .frame(width: Theme.gridSliderWidth)
                    .accessibilityLabel("Thumbnail size")
            }
            if pane == .second {
                Spacer(minLength: 0)
                Button { model.swapCompared() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .help("Swap Images (X)")
                    .accessibilityLabel("Swap Images")
                    .disabled(!model.availability.canSwap)
                Button { model.leaveCompare() } label: { Image(systemName: "xmark") }
                    .help("Stop Comparing (Esc)")
                    .accessibilityLabel("Stop Comparing")
            }
        }
        // Fades only when a different file arrives, never on zoom.
        .animation(Theme.Motion.fade(Theme.Motion.stripFade), value: model.list.current)
        .buttonStyle(.borderless)
        .font(Theme.strip)
        .foregroundStyle(Theme.labelStrip)
        .lineLimit(1)
        .padding(.horizontal, Theme.stripPadding)
        .frame(maxWidth: .infinity, minHeight: Theme.stripHeight, maxHeight: Theme.stripHeight, alignment: .leading)
        .glass(.chrome, in: Capsule())
        // Floats over the canvas (docs/DESIGN.md "Window layout"); fit keeps the image clear of it through `CanvasInsets`.
        .padding(.horizontal, Theme.stripSideInset)
        .padding(.bottom, Theme.stripBottomInset)
    }

    private var fields: [String] {
        if model.isGrid { return gridFields }
        if let pane { return paneFields(pane) }
        if let size = model.unsavedSize { return StatusLine.unsaved(pixelSize: size, zoomPercent: model.zoomPercent).fields }
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        guard model.list.current != nil, !model.isOpening else { return [] }
        // The image still on screen until the next one is shown: dropping its fields would shift the bar each swap.
        let info = model.fileInfo
        return StatusLine.make(pixelSize: info?.pixelSize, zoomPercent: model.zoomPercent, fileBytes: info?.bytes,
                               index: model.list.index, count: model.list.urls.count,
                               page: model.page, pageCount: model.pageCount,
                               frame: model.player.pausedFrame, frameCount: model.player.frameCount,
                               modified: info?.modified).fields
    }

    /// Name, pixel size, zoom, file size and date of the pane's picture; the position stays in the title.
    private func paneFields(_ pane: CompareSession.Pane) -> [String] {
        switch pane {
        case .first:
            guard let url = model.list.current, !model.isOpening else { return [] }
            let info = model.fileInfo
            return StatusLine.pane(name: url.lastPathComponent, pixelSize: info?.pixelSize, zoomPercent: model.zoomPercent,
                                   fileBytes: info?.bytes, modified: info?.modified).fields
        case .second:
            // The picture on screen and its details, until the next file's decode lands with its own.
            guard let session = model.compareSession, let info = session.info, session.image != nil else { return [] }
            return StatusLine.pane(name: info.url.lastPathComponent, pixelSize: info.pixelSize,
                                   zoomPercent: model.secondZoomPercent, fileBytes: info.bytes, modified: info.modified).fields
        }
    }

    /// The focused file's pixel size, file size, position and date (no zoom), or "12 of 120 selected".
    private var gridFields: [String] {
        let count = model.list.urls.count
        if model.gridSelection.count > 1 { return StatusLine.selection(count: model.gridSelection.count, total: count).fields }
        guard let focus = model.gridFocus, let index = model.list.urls.firstIndex(of: focus) else { return [] }
        let info = model.gridInfo
        return StatusLine.make(pixelSize: info?.pixelSize, zoomPercent: nil, fileBytes: info?.bytes, index: index, count: count,
                               page: 0, pageCount: 1, modified: info?.modified).fields
    }
}
