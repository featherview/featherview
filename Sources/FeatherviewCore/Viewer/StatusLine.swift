import CoreGraphics
import Foundation

/// The viewer's status bar text: one string per field, unknown values left out.
public struct StatusLine: Equatable, Sendable {
    public var fields: [String]

    /// `index`, `page` and `frame` are 0-based; the page shows only for multi-page files, the frame field
    /// only for animations: the frame count while playing (`frame` nil), the frame shown while paused.
    public static func make(pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?, index: Int, count: Int,
                            page: Int, pageCount: Int, frame: Int? = nil, frameCount: Int = 1,
                            modified: Date?) -> StatusLine {
        var fields = describe(pixelSize: pixelSize, zoomPercent: zoomPercent, fileBytes: fileBytes)
        fields.append(String(localized: "\((index + 1).formatted()) / \(count.formatted())"))
        if pageCount > 1 {
            fields.append(String(localized: "page \((page + 1).formatted()) / \(pageCount.formatted())"))
        }
        if frameCount > 1 {
            if let frame {
                fields.append(String(localized: "frame \((frame + 1).formatted()) / \(frameCount.formatted())"))
            } else {
                fields.append(String(localized: "\(frameCount) frames"))
            }
        }
        if let modified {
            fields.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return StatusLine(fields: fields)
    }

    /// An image without a file (pasted from the clipboard): size and zoom only.
    public static func unsaved(pixelSize: CGSize?, zoomPercent: Int?) -> StatusLine {
        StatusLine(fields: describe(pixelSize: pixelSize, zoomPercent: zoomPercent, fileBytes: nil))
    }

    /// The thumbnail grid's status bar while more than one cell is selected.
    public static func selection(count: Int, total: Int) -> StatusLine {
        StatusLine(fields: [String(localized: "\(count.formatted()) of \(total.formatted()) selected")])
    }

    /// One compare pane's strip: the name, then the fields `make` writes, without position, page or frame.
    public static func pane(name: String, pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?,
                            modified: Date?) -> StatusLine {
        var fields = [name] + describe(pixelSize: pixelSize, zoomPercent: zoomPercent, fileBytes: fileBytes)
        if let modified {
            fields.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return StatusLine(fields: fields)
    }

    private static func describe(pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?) -> [String] {
        var fields: [String] = []
        if let pixelSize {
            let width = Int(pixelSize.width).formatted(), height = Int(pixelSize.height).formatted()
            fields.append(String(localized: "\(width) × \(height)"))
        }
        if let zoomPercent {
            fields.append((Double(zoomPercent) / 100).formatted(.percent))
        }
        if let fileBytes {
            fields.append(ByteCountFormatter.string(fromByteCount: Int64(fileBytes), countStyle: .file))
        }
        return fields
    }
}
