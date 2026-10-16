import CoreGraphics
import Foundation

/// The viewer's status bar text: one string per field, unknown values left out.
public struct StatusLine: Equatable, Sendable {
    public var fields: [String]

    /// `index` and `page` are 0-based; the page shows only for multi-page files.
    public static func make(pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?, index: Int, count: Int,
                            page: Int, pageCount: Int, modified: Date?) -> StatusLine {
        var fields: [String] = []
        if let pixelSize {
            let width = Int(pixelSize.width).formatted(), height = Int(pixelSize.height).formatted()
            fields.append(String(localized: "\(width) × \(height)"))
        }
        if let zoomPercent {
            fields.append(String(localized: "\(zoomPercent.formatted()) %"))
        }
        if let fileBytes {
            fields.append(ByteCountFormatter.string(fromByteCount: Int64(fileBytes), countStyle: .file))
        }
        fields.append(String(localized: "\((index + 1).formatted()) / \(count.formatted())"))
        if pageCount > 1 {
            fields.append(String(localized: "page \((page + 1).formatted()) / \(pageCount.formatted())"))
        }
        if let modified {
            fields.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return StatusLine(fields: fields)
    }
}
