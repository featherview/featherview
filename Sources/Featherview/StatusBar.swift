import FeatherviewCore
import SwiftUI

/// One line along the bottom of the viewer (spec "Viewer"): pixel size, zoom, file size, position, page, date.
/// Its own view, so the values changing per image re-evaluate only this, not the window's toolbar.
struct StatusBar: View {
    let model: ViewerModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 { Divider().frame(height: 11) }
                Text(field)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .background(.bar)
    }

    private var fields: [String] {
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        guard let url = model.list.current, !model.isOpening else { return [] }
        let info = model.fileInfo?.url == url ? model.fileInfo : nil
        return StatusLine.make(pixelSize: info?.pixelSize, zoomPercent: model.zoomPercent, fileBytes: info?.bytes,
                               index: model.list.index, count: model.list.urls.count,
                               page: model.page, pageCount: model.pageCount, modified: info?.modified).fields
    }
}
