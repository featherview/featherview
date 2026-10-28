import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import libwebp
@testable import FeatherviewCore
import FeatherviewJXL

/// Test images are generated, never committed: tiny, exact, and no licensing questions.
enum Fixtures {
    /// The repository's root folder, for tests that read files shipped with the app.
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Gives `ImageEncoder` its JPEG XL encoder, as the app does at launch: `_ = Fixtures.jxl` before writing JPEG XL.
    static let jxl: Void = { ImageEncoder.jxlEncoder = JXLEncoder.encode }()

    /// An x86_64 test run on Apple Silicon. Core Graphics' x86_64 PDF parser on macOS 27 (which no Intel Mac
    /// runs) crashes now and then on a broken PDF there, so tests feeding it broken PDFs skip under Rosetta.
    static let underRosetta: Bool = {
        var translated: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }()

    /// Integers as big- and little-endian bytes, for building files byte by byte (only the low bytes count).
    static func be16(_ v: Int) -> [UInt8] { [8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
    static func be32(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
    static func le16(_ v: Int) -> [UInt8] { [0, 8].map { UInt8(truncatingIfNeeded: v >> $0) } }
    static func le32(_ v: Int) -> [UInt8] { [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: v >> $0) } }

    /// One colour (R, G, B, A) all over.
    static func solid(_ width: Int, _ height: Int, _ p: (UInt8, UInt8, UInt8, UInt8)) -> RGBAImage {
        RGBAImage(width: width, height: height, pixels: (0..<width * height).flatMap { _ in [p.0, p.1, p.2, p.3] })
    }

    /// `image` encoded as `type` in memory; `orientation` (the EXIF tag) is written only when given.
    static func encoded(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary })
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A PDF with one page of each size (points), `rotate` as each page's Rotate, and a red rectangle `fill`
    /// of each side from its lower-left corner (1: the whole page) on a transparent page.
    @discardableResult
    static func writePDF(to url: URL, pages sizes: [CGSize], rotate: Int = 0, fill: CGFloat = 1) throws -> URL {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        for size in sizes {
            var box = CGRect(origin: .zero, size: size)
            var info: [CFString: Any] = [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            if rotate != 0 { info["Rotate" as CFString] = rotate }
            context.beginPDFPage(info as CFDictionary)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width * fill, height: size.height * fill))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

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

    /// A 64 × 32 picture in four quadrants, stored with `orientation`: top-leading red, top-trailing green,
    /// bottom-leading blue, bottom-trailing white (before the tag is applied).
    static func writeQuadrants(to url: URL, type: UTType, orientation: Int) throws -> URL {
        let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Core Graphics counts y from the bottom.
        let quadrants: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: 16, width: 32, height: 16), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: 32, y: 16, width: 32, height: 16), CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 0, width: 32, height: 16), CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: 32, y: 0, width: 32, height: 16), CGColor(red: 1, green: 1, blue: 1, alpha: 1)),
        ]
        for (rect, colour) in quadrants {
            context.setFillColor(colour)
            context.fill(rect)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, context.makeImage()!,
                                   [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// The upright decode's four corner colours as "RG/BW": top row, then bottom row ("?" for any other colour).
    static func corners(of url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) else { return "" }
        let (width, height) = (image.width, image.height)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)  // row 0 is the top
        func colour(_ x: Int, _ y: Int) -> String {
            let i = (y * width + x) * 4
            switch (bytes[i] > 128, bytes[i + 1] > 128, bytes[i + 2] > 128) {
            case (true, false, false): return "R"
            case (false, true, false): return "G"
            case (false, false, true): return "B"
            case (true, true, true): return "W"
            default: return "?"
            }
        }
        let (l, t, r, b) = (4, 4, width - 5, height - 5)  // clear of compression bleed at edges and borders
        return colour(l, t) + colour(r, t) + "/" + colour(l, b) + colour(r, b)
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
    /// An HDR image in the quadrants of `writeQuadrants`, red and white 4× SDR bright, stored with `orientation`:
    /// with an ISO gain map, or as PQ HDR (`pq`, no gain map). macOS 15+ only.
    @available(macOS 15, *)
    @discardableResult
    static func writeHDRGainMap(to url: URL, type: UTType = .heic, orientation: Int = 1, pq: Bool = false) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        let quadrants: [(CGRect, [CGFloat])] = [  // Core Graphics counts y from the bottom
            (CGRect(x: 0, y: 24, width: 32, height: 24), [4, 0, 0, 1]),
            (CGRect(x: 32, y: 24, width: 32, height: 24), [0, 1, 0, 1]),
            (CGRect(x: 0, y: 0, width: 32, height: 24), [0, 0, 1, 1]),
            (CGRect(x: 32, y: 0, width: 32, height: 24), [4, 4, 4, 1]),
        ]
        for (rect, components) in quadrants {
            context.setFillColor(CGColor(colorSpace: space, components: components)!)
            context.fill(rect)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        // Without a content headroom ImageIO encodes a headroom of 1: a gain map that brightens nothing.
        CGImageDestinationAddImage(dest, CGImageCreateCopyWithContentHeadroom(4, context.makeImage()!)!, [
            kCGImageDestinationEncodeRequest: pq ? kCGImageDestinationEncodeToISOHDR : kCGImageDestinationEncodeToISOGainmap,
            kCGImagePropertyOrientation: orientation,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// An 8 × 8 picture with an Apple HDR gain map whose metadata, as on iPhone photos, is an XMP packet of
    /// its own (HDRGainMap:HDRGainMapVersion); the picture itself has none.
    @discardableResult
    static func writeAppleGainMap(to url: URL, type: UTType) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, solid(8, 8, (255, 0, 0, 255)).makeCGImage()!, nil)
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(metadata, "http://ns.apple.com/HDRGainMap/1.0/" as CFString,
                                                  "HDRGainMap" as CFString, nil)
        CGImageMetadataSetValueWithPath(metadata, nil, "HDRGainMap:HDRGainMapVersion" as CFString, 65536 as CFNumber)
        CGImageDestinationAddAuxiliaryDataInfo(dest, kCGImageAuxiliaryDataTypeHDRGainMap, [
            kCGImageAuxiliaryDataInfoData: Data(count: 16),
            kCGImageAuxiliaryDataInfoDataDescription: ["Width": 4, "Height": 4, "BytesPerRow": 4,
                                                       "PixelFormat": kCVPixelFormatType_OneComponent8] as [String: Any],
            kCGImageAuxiliaryDataInfoMetadata: metadata,
        ] as CFDictionary)
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

    /// An animation through ImageIO: one frame per delay (seconds), stored as `delayKey` in `dictionary`;
    /// `frame(n)` draws frame n (by default `animationFrame`). `fileProperties` are set before the frames.
    static func writeSequence(to url: URL, type: String, dictionary: CFString, delayKey: CFString,
                              delays: [Double], width: Int = 8, height: Int = 6, frame: ((Int) -> CGImage)? = nil,
                              fileProperties: [CFString: Any]? = nil) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, delays.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        if let fileProperties { CGImageDestinationSetProperties(dest, fileProperties as CFDictionary) }
        for (n, delay) in delays.enumerated() {
            CGImageDestinationAddImage(dest, frame?(n) ?? animationFrame(n, width: width, height: height),
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

    /// Puts an XMP packet (APP1) and IPTC records (APP13, `(dataset, value)` in record 2) right after a
    /// JPEG's start marker, as other apps write them, without ImageIO mirroring one into the other.
    @discardableResult
    static func insertJPEGMetadata(into url: URL, xmp: String? = nil, iptc: [(UInt8, String)] = []) throws -> URL {
        func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] { [0xFF, marker] + be16(body.count + 2) + body }
        var segments: [UInt8] = []
        if !iptc.isEmpty {
            var records: [UInt8] = []
            for (dataset, value) in iptc { records += [0x1C, 2, dataset] + be16(value.utf8.count) + Array(value.utf8) }
            if records.count % 2 == 1 { records.append(0) }
            segments += segment(0xED, Array("Photoshop 3.0\0".utf8) + Array("8BIM".utf8) + [0x04, 0x04, 0, 0]
                                + be32(records.count) + records)
        }
        if let xmp {
            segments += segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0".utf8) + Array(xmp.utf8))
        }
        var bytes = [UInt8](try Data(contentsOf: url))
        bytes.insert(contentsOf: segments, at: 2)
        try Data(bytes).write(to: url)
        return url
    }
}
