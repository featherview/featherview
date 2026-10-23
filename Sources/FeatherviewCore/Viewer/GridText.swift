import Foundation

/// The thumbnail grid's sentences: one file is named, several are counted (plural forms in the catalog).
public enum GridText {
    /// The window title's counter, after " — ".
    public static func counter(_ count: Int) -> String {
        String(localized: "\(count) images")
    }

    /// A cell's tooltip: the name, then the status bar's fields for that file once `info` is read.
    public static func tooltip(name: String, info: FileInfo?, index: Int, count: Int, failed: Bool) -> String {
        if failed { return String(localized: "Can't open \(name)") }
        guard let info else { return name }
        let details = StatusLine.make(pixelSize: info.pixelSize, zoomPercent: nil, fileBytes: info.bytes, index: index,
                                      count: count, page: 0, pageCount: 1, modified: info.modified).fields
        return name + "\n" + details.joined(separator: "  ·  ")
    }

    public static func trashFailed(_ failed: [URL]) -> String {
        if failed.count > 1 { return String(localized: "Couldn't move \(failed.count) images to the Trash") }
        let name = failed.first?.lastPathComponent ?? ""
        return String(localized: "Couldn't move \(name) to the Trash")
    }

    public static func transferFailed(_ failed: [URL], operation: FileOperation, folder: URL) -> String {
        let to = folder.lastPathComponent
        if failed.count > 1 {
            return operation == .move
                ? String(localized: "Couldn't move \(failed.count) images to \(to)")
                : String(localized: "Couldn't copy \(failed.count) images to \(to)")
        }
        let name = failed.first?.lastPathComponent ?? ""
        return operation == .move
            ? String(localized: "Couldn't move \(name) to \(to)")
            : String(localized: "Couldn't copy \(name) to \(to)")
    }

    public static func confirm(_ urls: [URL], operation: FileOperation, folder: URL) -> String {
        let to = folder.lastPathComponent
        if urls.count > 1 {
            return operation == .move
                ? String(localized: "Move \(urls.count) images to \(to)?")
                : String(localized: "Copy \(urls.count) images to \(to)?")
        }
        let name = urls.first?.lastPathComponent ?? ""
        return operation == .move
            ? String(localized: "Move \(name) to \(to)?")
            : String(localized: "Copy \(name) to \(to)?")
    }
}
