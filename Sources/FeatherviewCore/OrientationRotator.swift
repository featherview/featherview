import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Rotation: Sendable {
    case clockwise, counterClockwise
}

public enum RotateError: Error, Equatable {
    case unsupportedFormat, unreadable, writeFailed
}

public enum OrientationRotator {
    /// Formats whose EXIF orientation tag is honoured everywhere, so rotating needs no re-encode.
    static let supported: [UTType] = [.jpeg, .heic, .tiff]

    /// EXIF orientation after one clockwise quarter turn (mirrored values included).
    static let clockwise: [Int: Int] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]

    public static func next(_ orientation: Int, _ rotation: Rotation) -> Int {
        switch rotation {
        case .clockwise: clockwise[orientation] ?? 6
        case .counterClockwise: clockwise.first { $0.value == orientation }?.key ?? 8
        }
    }

    /// Lossless: only the orientation tag changes, pixel data is copied untouched.
    /// Writes a temp file next to the original and swaps it in, so a failure never damages the original.
    /// `page` is a page of a multi-page TIFF; only that page turns.
    public static func rotate(_ link: URL, _ rotation: Rotation, page: Int = 0) throws {
        let url = link.resolvingSymlinksInPath()  // replaceItemAt can't swap a symlink; rotate its target
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { throw RotateError.unreadable }
        // Content, not extension: a PNG named .jpg must still be refused.
        guard let type = UTType(sourceType as String),
              supported.contains(where: { type.conforms(to: $0) }) else { throw RotateError.unsupportedFormat }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, page, nil) as? [CFString: Any]
        else { throw RotateError.unreadable }
        let current = props[kCGImagePropertyOrientation] as? Int ?? 1
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".featherview-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }  // no-op once swapped in
        let count = CGImageSourceGetCount(source)
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, sourceType, count, nil) else {
            throw RotateError.writeFailed
        }
        if page == 0 {
            let options: [CFString: Any] = [
                kCGImageDestinationOrientation: next(current, rotation),
                kCGImageDestinationMergeMetadata: true,
            ]
            guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, nil) else {
                throw RotateError.writeFailed
            }
        } else {
            // CopyImageSource only sets page 0's orientation, so every page is written again with its own.
            // shortcut: this re-encodes the pages (lossless for LZW, ZIP and uncompressed TIFF, lossy for
            // JPEG-compressed TIFF pages); find a tag-only rewrite if people rotate such pages.
            for index in 0..<count {
                var pageProps = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
                if index == page {
                    let turned = next(current, rotation)
                    pageProps[kCGImagePropertyOrientation] = turned
                    var tiff = pageProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                    tiff[kCGImagePropertyTIFFOrientation] = turned
                    pageProps[kCGImagePropertyTIFFDictionary] = tiff
                }
                CGImageDestinationAddImageFromSource(dest, source, index, pageProps as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else { throw RotateError.writeFailed }
        }
        do { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) }
        catch { throw RotateError.writeFailed }
    }
}
