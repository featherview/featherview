import Foundation

/// What the status bar and the overlay show about a file's page: its pixel size, bytes and date.
public struct FileInfo: Equatable, Sendable {
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

    /// The info to put on screen with an image of `url` / `page`: `known` is its prefetched page-0 read,
    /// `current` the one on screen, kept only for another page > 0 decode of the same page (a zoom change).
    /// Never another file's or page's, nor page 0's after a rotation dropped `known`: none is better than wrong.
    public static func shown(url: URL, page: Int, known: FileInfo?, current: FileInfo?) -> FileInfo? {
        let candidate = page == 0 ? known : current
        return candidate?.isFor(url, page: page) == true ? candidate : nil
    }
}
