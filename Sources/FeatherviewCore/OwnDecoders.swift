import CoreGraphics
import Foundation
import os

/// A format macOS can't read, so Featherview decodes it itself (spec "Formats").
public struct OwnFormat: Sendable {
    /// Short name for the About window, e.g. "QOI".
    public let name: String
    /// Lowercase file extensions, without the dot.
    public let extensions: [String]
    /// True if a file can hold several pages (DCX); the viewer then asks `pageCount`.
    public let hasPages: Bool
    /// Pixel size of `page` from the header alone; nil if the file isn't one.
    public let size: @Sendable (_ data: Data, _ page: Int) -> CGSize?
    public let pageCount: @Sendable (_ data: Data) -> Int
    /// Decodes `page`. Raster formats ignore `maxPixelSize` and return full size (ImageDecoder scales
    /// down); vector formats render at it.
    public let decode: @Sendable (_ data: Data, _ page: Int, _ maxPixelSize: Int?) throws -> CGImage

    public init(name: String, extensions: [String], hasPages: Bool = false,
                size: @escaping @Sendable (Data, Int) -> CGSize?,
                pageCount: @escaping @Sendable (Data) -> Int = { _ in 1 },
                decode: @escaping @Sendable (Data, Int, Int?) throws -> CGImage) {
        self.name = name
        self.extensions = extensions
        self.hasPages = hasPages
        self.size = size
        self.pageCount = pageCount
        self.decode = decode
    }

    /// A raster format: decoders return `RGBAImage`, sizes come from the header.
    static func raster(name: String, extensions: [String], hasPages: Bool = false,
                       size: @escaping @Sendable (Data, Int) throws -> (width: Int, height: Int),
                       pageCount: @escaping @Sendable (Data) -> Int = { _ in 1 },
                       decode: @escaping @Sendable (Data, Int) throws -> RGBAImage) -> OwnFormat {
        OwnFormat(name: name, extensions: extensions, hasPages: hasPages,
                  size: { data, page in (try? size(data, page)).map { CGSize(width: $0.width, height: $0.height) } },
                  pageCount: pageCount,
                  decode: { data, page, _ in
                      guard let image = try decode(data, page).makeCGImage() else { throw OwnDecodeError.corrupt }
                      return image
                  })
    }
}

public enum OwnDecoders {
    /// Pure-Swift decoders in FeatherviewCore. The app adds the ones that need AppKit (SVG) with `register`.
    static let builtIn: [OwnFormat] = [
        QOICodec.format, PCXCodec.pcx, PCXCodec.dcx,
        XBMDecoder.format, XPMDecoder.format, WBMPDecoder.format,
        // Task 4
        // Task 5
    ]

    private static let formats = OSAllocatedUnfairLock(initialState: builtIn)

    public static var all: [OwnFormat] { formats.withLock { $0 } }

    /// Adds a decoder; a format already registered under one of its extensions is replaced.
    public static func register(_ format: OwnFormat) {
        formats.withLock { list in
            list.removeAll { !Set($0.extensions).isDisjoint(with: format.extensions) }
            list.append(format)
        }
    }

    /// By file extension only, like `ImageFormats.isDecodable`.
    public static func format(for url: URL) -> OwnFormat? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return formats.withLock { $0.first { $0.extensions.contains(ext) } }
    }
}
