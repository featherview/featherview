import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import libwebp

/// Test images are generated, never committed: tiny, exact, and no licensing questions.
enum Fixtures {
    /// The repository's root folder, for tests that read files shipped with the app.
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("featherview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid red image. `orientation` is the EXIF orientation tag, 1...8.
    /// `properties` are extra ImageIO metadata dictionaries (EXIF, GPS, ...).
    /// `bitsPerComponent` 16 makes a deep SDR image (16-bit PNG/TIFF, 32-bit float EXR); 32 a float TIFF.
    @discardableResult
    static func writeImage(to url: URL, width: Int, height: Int, type: UTType = .jpeg,
                           orientation: Int = 1, properties: [CFString: Any] = [:],
                           bitsPerComponent: Int = 8) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                | (bitsPerComponent == 32 ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : 0))!
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

    /// Solid frame `n` of an animation: red = 40·n, so tests can tell frames apart.
    static func animationFrame(_ n: Int, width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: CGFloat(40 * n % 256) / 255, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// An animation through ImageIO: one frame per delay (seconds), stored as `delayKey` in `dictionary`.
    private static func writeSequence(to url: URL, type: String, dictionary: CFString, delayKey: CFString,
                                      delays: [Double], width: Int, height: Int) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, delays.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        for (n, delay) in delays.enumerated() {
            CGImageDestinationAddImage(dest, animationFrame(n, width: width, height: height),
                                       [dictionary: [delayKey: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    @discardableResult
    static func writeAnimatedGIF(to url: URL, delays: [Double], width: Int = 8, height: Int = 6) throws -> URL {
        try writeSequence(to: url, type: UTType.gif.identifier, dictionary: kCGImagePropertyGIFDictionary,
                          delayKey: kCGImagePropertyGIFDelayTime, delays: delays, width: width, height: height)
    }

    @discardableResult
    static func writeAPNG(to url: URL, delays: [Double], width: Int = 8, height: Int = 6) throws -> URL {
        try writeSequence(to: url, type: UTType.png.identifier, dictionary: kCGImagePropertyPNGDictionary,
                          delayKey: kCGImagePropertyAPNGDelayTime, delays: delays, width: width, height: height)
    }

    @discardableResult
    static func writeHEICS(to url: URL, delays: [Double], width: Int = 8, height: Int = 6) throws -> URL {
        try writeSequence(to: url, type: "public.heics", dictionary: kCGImagePropertyHEICSDictionary,
                          delayKey: kCGImagePropertyHEICSDelayTime, delays: delays, width: width, height: height)
    }

    /// An animated WebP through libwebp's `WebPAnimEncoder` (ImageIO can't write WebP), lossless.
    @discardableResult
    static func writeAnimatedWebP(to url: URL, delays: [Double], width: Int = 8, height: Int = 6) throws -> URL {
        var options = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInit(&options) != 0,
              let encoder = WebPAnimEncoderNew(Int32(width), Int32(height), &options) else { throw CocoaError(.fileWriteUnknown) }
        defer { WebPAnimEncoderDelete(encoder) }
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw CocoaError(.fileWriteUnknown) }
        config.lossless = 1
        var timestamp: Int32 = 0
        for (n, delay) in delays.enumerated() {
            var picture = WebPPicture()
            guard WebPPictureInit(&picture) != 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { WebPPictureFree(&picture) }
            picture.width = Int32(width)
            picture.height = Int32(height)
            picture.use_argb = 1
            let red = UInt8(40 * n % 256)
            let pixels = (0..<width * height * 4).map { i -> UInt8 in i % 4 == 0 ? red : i % 4 == 3 ? 255 : 0 }
            guard pixels.withUnsafeBufferPointer({ WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(width * 4)) }) != 0,
                  WebPAnimEncoderAdd(encoder, &picture, timestamp, &config) != 0 else { throw CocoaError(.fileWriteUnknown) }
            timestamp += Int32((delay * 1000).rounded())
        }
        var data = WebPData()
        guard WebPAnimEncoderAdd(encoder, nil, timestamp, nil) != 0,
              WebPAnimEncoderAssemble(encoder, &data) != 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { WebPDataClear(&data) }
        try Data(bytes: data.bytes, count: data.size).write(to: url)
        return url
    }

    /// A red 4000 × 3000 JPEG carrying the EXIF APP1 segment, with its embedded 160 × 120 thumbnail, of a
    /// blue JPEG of the same size: a decode shows red, the embedded thumbnail blue.
    @discardableResult
    static func writeJPEGWithForeignThumbnail(to url: URL) throws -> URL {
        func jpeg(red: CGFloat, blue: CGFloat, embedThumbnail: Bool) throws -> [UInt8] {
            let context = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(dest, context.makeImage()!,
                                       [kCGImageDestinationEmbedThumbnail: embedThumbnail,
                                        kCGImagePropertyOrientation: 1] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
            return [UInt8](data as Data)
        }
        /// The APP1 (EXIF) segment's bytes, marker included; segments end at start-of-scan.
        func app1(_ bytes: [UInt8]) -> Range<Int>? {
            var i = 2
            while i + 4 <= bytes.count, bytes[i] == 0xFF, bytes[i + 1] != 0xDA {
                let end = i + 2 + (Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]))
                if bytes[i + 1] == 0xE1 { return i..<end }
                i = end
            }
            return nil
        }
        let blue = try jpeg(red: 0, blue: 1, embedThumbnail: true)
        var red = try jpeg(red: 1, blue: 0, embedThumbnail: false)
        guard let exif = app1(blue) else { throw CocoaError(.fileWriteUnknown) }
        let at = app1(red) ?? 2..<2
        red.replaceSubrange(at, with: blue[exif])
        try Data(red).write(to: url)
        return url
    }
}
