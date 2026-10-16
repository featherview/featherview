import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Test images are generated, never committed: tiny, exact, and no licensing questions.
enum Fixtures {
    static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("featherview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid red image. `orientation` is the EXIF orientation tag, 1...8.
    /// `properties` are extra ImageIO metadata dictionaries (EXIF, GPS, ...).
    @discardableResult
    static func writeImage(to url: URL, width: Int, height: Int, type: UTType = .jpeg,
                           orientation: Int = 1, properties: [CFString: Any] = [:]) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        var props = properties
        props[kCGImagePropertyOrientation] = orientation
        CGImageDestinationAddImage(dest, context.makeImage()!, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// A file with an image extension but garbage content.
    static func writeCorrupt(to url: URL) throws -> URL {
        try Data("not an image".utf8).write(to: url)
        return url
    }
}
