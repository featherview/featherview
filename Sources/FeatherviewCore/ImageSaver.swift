import CoreGraphics
import Foundation

/// Save As from the viewer (spec "Menu commands"), and the pages both it and the batch write.
public enum ImageSaver {
    /// The pages to write: every page for PDF and for TIFF with "keep all pages", else just `page`.
    /// Upright, at most `maxPixelSize` on the longest side (nil = full size).
    // shortcut: all pages are decoded before encoding, so a 200-page TIFF holds them all in memory; stream pages if that bites.
    public static func pages(of url: URL, page: Int = 0, for format: OutputFormat, options: FormatOptions,
                             maxPixelSize: Int? = nil) throws -> [CGImage] {
        let all = format.writer == .pdf || (format.optionFields.contains(.keepAllPages) && options.keepAllPages)
        let indices = all ? Array(0..<ImageDecoder.pageCount(of: url)) : [page]
        return try indices.map { try ImageDecoder.decode(url, maxPixelSize: maxPixelSize, page: $0) }
    }

    /// Writes `source` (its `page`) as `format` to `destination`. The save panel has already asked
    /// before replacing a file; an existing file is replaced only once the new one is completely
    /// written, so a failure leaves it as it was. Reads and writes files: call it off the main thread.
    public static func save(_ source: URL, page: Int, to destination: URL, as format: OutputFormat,
                            options: FormatOptions) throws {
        let destination = destination.resolvingSymlinksInPath()  // replaceItemAt can't replace a link: replace what it points to
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isFolder), isFolder.boolValue {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])  // never replace a folder
        }
        let data = try ImageEncoder.encode(pages(of: source, page: page, for: format, options: options),
                                           as: format, options: options, metadataFrom: source)
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".featherview-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }
}
