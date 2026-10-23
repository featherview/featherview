import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Rotation: Sendable {
    case clockwise, counterClockwise
}

/// A mirror of the picture as shown: left–right or top–bottom.
public enum Flip: Sendable {
    case horizontal, vertical
}

public enum OrientationChange: Equatable, Sendable {
    case rotate(Rotation)
    case flip(Flip)
}

public enum RotateError: Error, Equatable {
    case unsupportedFormat, unreadable, writeFailed
    /// A later page of a multi-page TIFF: turning it would re-encode every page.
    case notFirstPage
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

    /// EXIF orientation after mirroring the displayed picture left–right / top–bottom.
    static let horizontal: [Int: Int] = [1: 2, 2: 1, 3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7]
    static let vertical: [Int: Int] = [1: 4, 2: 3, 3: 2, 4: 1, 5: 8, 6: 7, 7: 6, 8: 5]

    /// An unknown orientation counts as 1.
    public static func next(_ orientation: Int, _ change: OrientationChange) -> Int {
        switch change {
        case .rotate(let rotation): next(orientation, rotation)
        case .flip(.horizontal): horizontal[orientation] ?? 2
        case .flip(.vertical): vertical[orientation] ?? 4
        }
    }

    public static func rotate(_ link: URL, _ rotation: Rotation, page: Int = 0) throws {
        try apply(link, .rotate(rotation), page: page)
    }

    /// Lossless: only the orientation tag changes, pixel data is copied untouched.
    /// Writes a temp file next to the original and swaps it in, so a failure never damages the original.
    /// `page` is a page of a multi-page TIFF. ImageIO can only set the first page's tag without
    /// re-encoding, so later pages are refused (spec "Rotate").
    public static func apply(_ link: URL, _ change: OrientationChange, page: Int = 0) throws {
        guard page == 0 else { throw RotateError.notFirstPage }
        let url = link.resolvingSymlinksInPath()  // replaceItemAt can't swap a symlink; rotate its target
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { throw RotateError.unreadable }
        // Content, not extension: a PNG named .jpg must still be refused.
        guard let type = UTType(sourceType as String),
              supported.contains(where: { type.conforms(to: $0) }) else { throw RotateError.unsupportedFormat }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw RotateError.unreadable }
        let current = props[kCGImagePropertyOrientation] as? Int ?? 1
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".featherview-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }  // no-op once swapped in
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, sourceType, 1, nil) else {
            throw RotateError.writeFailed
        }
        let target = next(current, change)
        let options: [CFString: Any] = [
            kCGImageDestinationOrientation: target,
            kCGImageDestinationMergeMetadata: true,
        ]
        guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, nil)
            || (type.conforms(to: .heic) && rewriteHEIF(url, source, to: temp, orientation: target))
        else { throw RotateError.writeFailed }
        do { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) }
        catch { throw RotateError.writeFailed }
    }

    /// ImageIO refuses to change the orientation of a HEIC with an ISO gain map; `HEIFOrientation` can.
    /// The result must read back with the new orientation, decode, and keep its gain map, or it isn't used.
    static func rewriteHEIF(_ url: URL, _ source: CGImageSource, to temp: URL, orientation: Int) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let rewritten = HEIFOrientation.setting(orientation, in: data),
              (try? rewritten.write(to: temp)) != nil,
              let check = CGImageSourceCreateWithURL(temp as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyOrientation] as? Int ?? 1 == orientation,
              CGImageSourceCreateImageAtIndex(check, 0, nil) != nil
        else { return false }
        guard #available(macOS 15, *) else { return true }
        return [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].allSatisfy {
            (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) == nil)
                == (CGImageSourceCopyAuxiliaryDataInfoAtIndex(check, 0, $0) == nil)
        }
    }
}
