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
        let modified = url.modificationDate
        let size = ImageDecoder.displaySize(of: url, page: page)
        // `{size}` is page 0's on every page.
        let fileSize = page == 0 ? size : ImageDecoder.displaySize(of: url)
        return FileInfo(url: url, page: page, pixelSize: size,
                        bytes: url.fileSize, modified: modified,
                        values: OverlayTemplate.fileValues(size: fileSize, modified: modified))
    }

    /// The same values under a new URL: after a rename the picture stays without a new read.
    public func moved(to url: URL) -> FileInfo {
        FileInfo(url: url, page: page, pixelSize: pixelSize, bytes: bytes, modified: modified, values: values)
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
