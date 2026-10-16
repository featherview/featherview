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
    /// `bitsPerComponent` 16 makes a deep SDR image (16-bit PNG/TIFF, half-float EXR).
    @discardableResult
    static func writeImage(to url: URL, width: Int, height: Int, type: UTType = .jpeg,
                           orientation: Int = 1, properties: [CFString: Any] = [:],
                           bitsPerComponent: Int = 8) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
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

    /// A TIFF with `pages` solid red pages; page n is `width + n`×`height`, so tests can tell pages apart.
    @discardableResult
    static func writeMultiPageTIFF(to url: URL, pages: Int, width: Int = 8, height: Int = 4) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, pages, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        for page in 0..<pages {
            let context = CGContext(
                data: nil, width: width + page, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width + page, height: height))
            CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
    /// A gain-map image: left half 4× SDR white, right half a dark colour. macOS 15+ only.
    @available(macOS 15, *)
    @discardableResult
    static func writeHDRGainMap(to url: URL, type: UTType = .heic) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [4, 4, 4, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        context.setFillColor(CGColor(colorSpace: space, components: [0.5, 0.2, 0.1, 1])!)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 48))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, context.makeImage()!,
                                   [kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
