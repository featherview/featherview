import Foundation

/// What the status bar and the overlay show about a file's page: its pixel size, bytes and date.
public struct FileInfo: Sendable {
    public let url: URL
    public let page: Int
    public let pixelSize: CGSize?
    public let bytes: Int?
    public let modified: Date?
    /// The overlay's `{size}` and `{date}`.
    public let values: [String: String]

    /// Reads the file; call off the main thread (it touches the disk).
    public static func read(url: URL, page: Int) -> FileInfo {
        let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileInfo(url: url, page: page, pixelSize: ImageDecoder.displaySize(of: url, page: page),
                        bytes: resources?.fileSize, modified: resources?.contentModificationDate,
                        values: OverlayTemplate.fileValues(of: url))
    }

    /// A read for another page of the same file has another pixel size.
    public func isFor(_ url: URL?, page: Int) -> Bool { self.url == url && self.page == page }
}
