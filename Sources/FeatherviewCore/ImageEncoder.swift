import CoreGraphics
import Foundation
import ImageIO

public enum EncodeError: Error, Equatable {
    case failed
}

/// Turns upright pixels into a file's bytes in any `OutputFormat`, with its options (spec "Format options").
public enum ImageEncoder {
    /// `pages` are upright (orientation applied); only TIFF with "keep all pages" and PDF write more
    /// than the first. Metadata of `source` (camera, EXIF, GPS, IPTC) is kept where the format and
    /// "keep metadata" allow; the orientation tag is always 1. `dpi` is written for ImageIO formats.
    public static func encode(_ pages: [CGImage], as format: OutputFormat, options: FormatOptions,
                              metadataFrom source: URL? = nil, dpi: Int? = nil) throws -> Data {
        guard let first = pages.first else { throw EncodeError.failed }
        switch format.writer {
        case .pdf: return try pdf(pages, options)
        case .pbm: return NetpbmEncoder.pbm(try rgba(first))
        case .pgm: return NetpbmEncoder.pgm(try rgba(first))
        case .ppm: return NetpbmEncoder.ppm(try rgba(first))
        case .qoi: return QOICodec.encode(try rgba(first))
        case .webp:
            return try WebPEncoder.encode(try rgba(first), quality: options.quality, lossless: options.lossless,
                                          effort: options.effort, kind: options.webpKind)
        case .pcx:  // PCX's header can't hold every size
            guard let data = try? PCXCodec.encode(try rgba(first)) else { throw EncodeError.failed }
            return data
        case .imageIO(let type):
            var metadata = options.keepMetadata ? source.map(metadataProperties) ?? [:] : [:]
            if let dpi, dpi > 0 {
                metadata[kCGImagePropertyDPIWidth] = dpi
                metadata[kCGImagePropertyDPIHeight] = dpi
            }
            if format.optionFields.contains(.targetSize), let kb = options.targetSizeKB, kb > 0 {
                return try targetSize(first, type: type, format: format, options: options, metadata: metadata,
                                      bytes: min(kb, Int.max / 1024) * 1024)  // a stored setting may be any Int
            }
            var images = [first]
            if format.optionFields.contains(.keepAllPages), options.keepAllPages { images = pages }
            if let sizes = iconSizes[format.id] { images = [try iconSquare(first, allowed: sizes)] }
            var props = properties(format, options, metadata)
            if #available(macOS 15, *), ["heic", "avif"].contains(format.id), first.colorSpace.map(isHDR) == true {
                props[kCGImageDestinationEncodeRequest] = kCGImageDestinationEncodeToISOGainmap  // else ImageIO writes SDR
            }
            return try imageIO(images, type: type, properties: props)
        }
    }

    /// PQ/HLG or extended range: pixels that may go above SDR white.
    static func isHDR(_ space: CGColorSpace) -> Bool {
        CGColorSpaceUsesITUR_2100TF(space) || CGColorSpaceUsesExtendedRange(space)
    }

    /// ICO and ICNS only take squares of these sizes (tested with ImageIO on macOS 27).
    static let iconSizes: [String: [Int]] = ["ico": [16, 32, 48, 64, 128, 256], "icns": [16, 32, 128, 256, 512]]

    static func properties(_ format: OutputFormat, _ options: FormatOptions, _ metadata: [CFString: Any]) -> [CFString: Any] {
        var props = metadata
        props[kCGImagePropertyOrientation] = 1
        let fields = format.optionFields
        if fields.contains(.quality) {
            var quality = Double(min(max(options.quality, 1), 100)) / 100
            if fields.contains(.lossless), options.lossless { quality = 1 }
            // ImageIO fails to write AVIF at 1.0 (macOS 27).
            if format.id == "avif" { quality = min(quality, 0.99) }
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        if fields.contains(.progressive), options.progressive {
            props[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true]
        }
        if fields.contains(.interlaced), options.interlaced {
            props[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGInterlaceType: 1]
        }
        if fields.contains(.tiffCompression) {
            var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = options.tiffCompression.rawValue
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        return props
    }

    static func imageIO(_ images: [CGImage], type: String, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, images.count, nil)
        else { throw EncodeError.failed }
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw EncodeError.failed }
        return data as Data
    }

    /// The highest JPEG quality whose file fits `bytes`, by binary search (about 7 encodes);
    /// quality 1 if even that is too big.
    static func targetSize(_ image: CGImage, type: String, format: OutputFormat, options: FormatOptions,
                           metadata: [CFString: Any], bytes: Int) throws -> Data {
        var low = 1, high = 100
        var best: Data?
        while low <= high {
            let quality = (low + high) / 2
            let data = try imageIO([image], type: type,
                                   properties: properties(format, options.with { $0.quality = quality }, metadata))
            if data.count <= bytes { best = data; low = quality + 1 } else { high = quality - 1 }
        }
        if let best { return best }
        return try imageIO([image], type: type, properties: properties(format, options.with { $0.quality = 1 }, metadata))
    }

    /// Scaled to fit the largest allowed square (never enlarged), centred on transparency; a small
    /// image sits in the smallest allowed square that holds it.
    static func iconSquare(_ image: CGImage, allowed: [Int]) throws -> CGImage {
        let longest = max(image.width, image.height)
        let side = allowed.first { $0 >= longest } ?? allowed.last!
        let scale = min(1, Double(side) / Double(longest))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw EncodeError.failed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        guard let square = context.makeImage() else { throw EncodeError.failed }
        return square
    }

    /// One page per image, 1 pixel = 1 point. Photos go in as JPEG at the chosen quality (embedded
    /// as is); lossless, or an image with transparency (JPEG has none), goes in uncompressed and
    /// Core Graphics deflates it.
    static func pdf(_ pages: [CGImage], _ options: FormatOptions) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw EncodeError.failed }
        for page in pages {
            var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            var image = page
            let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(page.alphaInfo)
            if !options.lossless, !hasAlpha {
                let jpeg = try imageIO([page], type: "public.jpeg",
                                       properties: [kCGImageDestinationLossyCompressionQuality: Double(options.quality) / 100])
                guard let provider = CGDataProvider(data: jpeg as CFData),
                      let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                             intent: .defaultIntent) else { throw EncodeError.failed }
                image = embedded
            }
            let mediaBox = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: mediaBox] as CFDictionary)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func rgba(_ image: CGImage) throws -> RGBAImage {
        guard let pixels = RGBAImage(image) else { throw EncodeError.failed }
        return pixels
    }

    /// Keeps TIFF (camera make/model), EXIF, GPS and IPTC; drops what no longer matches the new pixels.
    static func metadataProperties(of input: URL) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return props }
        if var tiff = original[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil  // camera make/model, copyright, ...
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = original[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            props[kCGImagePropertyExifDictionary] = exif
        }
        props[kCGImagePropertyGPSDictionary] = original[kCGImagePropertyGPSDictionary]
        props[kCGImagePropertyIPTCDictionary] = original[kCGImagePropertyIPTCDictionary]
        return props
    }
}
