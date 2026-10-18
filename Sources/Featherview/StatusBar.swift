import FeatherviewCore
import SwiftUI

/// One line along the bottom of the viewer (spec "Viewer"): pixel size, zoom, file size, position, page, date.
/// Its own view, so the values changing per image re-evaluate only this, not the window's toolbar.
struct StatusBar: View {
    let model: ViewerModel

    var body: some View {
        HStack(spacing: Theme.stripGap) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 {
                    Theme.stripSeparator.frame(width: 1, height: Theme.stripSeparatorHeight)
                }
                Text(field)
            }
        }
        // Fades only when a different file arrives, never on zoom.
        .animation(Theme.Motion.fade(Theme.Motion.stripFade), value: model.list.current)
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
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        guard model.list.current != nil, !model.isOpening else { return [] }
        // The image still on screen until the next one is shown: dropping its fields would shift the bar each swap.
        let info = model.fileInfo
        return StatusLine.make(pixelSize: info?.pixelSize, zoomPercent: model.zoomPercent, fileBytes: info?.bytes,
                               index: model.list.index, count: model.list.urls.count,
                               page: model.page, pageCount: model.pageCount, modified: info?.modified).fields
    }
}
