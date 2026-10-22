import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A format Featherview can write (spec "Formats"): ImageIO's, PDF through Core Graphics, or our own encoders.
public struct OutputFormat: Hashable, Sendable, Identifiable {
    public enum Writer: Hashable, Sendable {
        /// A UTType identifier ImageIO writes.
        case imageIO(String)
        /// One page per image, drawn with Core Graphics (ImageIO's PDF ignores quality).
        case pdf
        case pbm, pgm, ppm, qoi, pcx
        /// libwebp (the one third-party encoder, spec "Formats").
        case webp
        /// libjxl: ImageIO reads JPEG XL but writes none.
        case jxl
    }

    /// Stable key, stored in settings: never change one once shipped. The file extension for known formats.
    public let id: String
    /// Short name shown in pickers: "JPEG", "JPEG 2000".
    public let name: String
    public let fileExtension: String
    public let writer: Writer
    /// Options shown for this format, in display order.
    public let optionFields: [FormatOption]
    public let defaultOptions: FormatOptions

    public static func == (a: OutputFormat, b: OutputFormat) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The effort slider's range: libjxl's 1...9 (10 needs its expert mode), libwebp's method 0...6.
    public var effortRange: ClosedRange<Int> { writer == .jxl ? 1...9 : 0...6 }

    public var type: UTType? {
        if case .imageIO(let identifier) = writer { return UTType(identifier) }
        return UTType(filenameExtension: fileExtension)
    }

    /// `url`'s name with this format's extension, for Save As. Not the UTType's preferred one:
    /// PGM and PPM share public.pbm (.pbm), and JPEG's is .jpeg where batch output writes .jpg.
    public func fileName(for url: URL) -> String {
        url.deletingPathExtension().appendingPathExtension(fileExtension).lastPathComponent
    }
}

/// One option of spec "Format options".
public enum FormatOption: String, Sendable, CaseIterable {
    case quality, lossless, progressive, keepMetadata, targetSize, interlaced, tiffCompression, keepAllPages,
         effort, webpKind
}

public enum TIFFCompression: Int, Codable, Sendable, CaseIterable {
    // The values are the TIFF tag's.
    case none = 1, lzw = 5, packBits = 32773, jpeg = 7, zip = 8
}

/// Every option of every format; each format uses its `optionFields`. Unknown or missing keys in
/// stored JSON fall back to the defaults, so adding an option never loses the user's others.
public struct FormatOptions: Codable, Equatable, Sendable {
    /// 1...100.
    public var quality = 80
    public var lossless = false
    public var progressive = false
    public var keepMetadata = true
    /// JPEG: a size in KB to reach by lowering the quality; nil = off.
    public var targetSizeKB: Int?
    public var interlaced = false
    public var tiffCompression = TIFFCompression.lzw
    public var keepAllPages = true
    /// WebP: libwebp's method, 0...6; higher is slower and smaller.
    public var effort = 4
    /// WebP: the spec's "preset".
    public var webpKind = WebPPictureKind.photo

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FormatOptions()
        quality = (try? c.decodeIfPresent(Int.self, forKey: .quality)) ?? d.quality
        lossless = (try? c.decodeIfPresent(Bool.self, forKey: .lossless)) ?? d.lossless
        progressive = (try? c.decodeIfPresent(Bool.self, forKey: .progressive)) ?? d.progressive
        keepMetadata = (try? c.decodeIfPresent(Bool.self, forKey: .keepMetadata)) ?? d.keepMetadata
        targetSizeKB = (try? c.decodeIfPresent(Int.self, forKey: .targetSizeKB)) ?? d.targetSizeKB
        interlaced = (try? c.decodeIfPresent(Bool.self, forKey: .interlaced)) ?? d.interlaced
        tiffCompression = (try? c.decodeIfPresent(TIFFCompression.self, forKey: .tiffCompression)) ?? d.tiffCompression
        keepAllPages = (try? c.decodeIfPresent(Bool.self, forKey: .keepAllPages)) ?? d.keepAllPages
        effort = (try? c.decodeIfPresent(Int.self, forKey: .effort)) ?? d.effort
        webpKind = (try? c.decodeIfPresent(WebPPictureKind.self, forKey: .webpKind)) ?? d.webpKind
    }

    func with(_ change: (inout FormatOptions) -> Void) -> FormatOptions {
        var copy = self
        change(&copy)
        return copy
    }
}

/// The formats this Mac can write, built at launch from ImageIO plus our own (spec "Formats").
public enum FormatRegistry {
    /// GPU texture formats and image sequences: ImageIO writes them, nobody saves photos as them.
    static let hidden: Set<String> = [
        "com.apple.atx", "org.khronos.ktx", "org.khronos.ktx2", "org.khronos.astc",
        "com.microsoft.dds", "public.pvr", "public.heics",
        "public.pbm",  // writes colour ASCII PPM under the .pbm name; ours writes real PBM
        "org.webmproject.webp",  // ours, through libwebp, if a newer ImageIO writes it too
        "public.jpeg-xl",  // ours, through libjxl, if a newer ImageIO writes it too
    ]

    /// Known ImageIO types: id (= extension), name, options, defaults.
    private static let known: [String: (id: String, name: String, fields: [FormatOption], defaults: FormatOptions)] = [
        "public.jpeg": ("jpg", "JPEG", [.quality, .progressive, .keepMetadata, .targetSize], FormatOptions()),
        "public.heic": ("heic", "HEIC", [.quality, .keepMetadata], FormatOptions()),
        "public.avif": ("avif", "AVIF", [.quality, .keepMetadata], FormatOptions()),
        "public.png": ("png", "PNG", [.interlaced], FormatOptions()),
        "public.tiff": ("tiff", "TIFF", [.tiffCompression, .keepAllPages], FormatOptions()),
        "com.compuserve.gif": ("gif", "GIF", [], FormatOptions()),
        "public.jpeg-2000": ("jp2", "JPEG 2000", [.lossless, .quality], FormatOptions().with { $0.quality = 90; $0.lossless = true }),
        "com.adobe.photoshop-image": ("psd", "PSD", [], FormatOptions()),
        "com.truevision.tga-image": ("tga", "TGA", [], FormatOptions()),
        "com.microsoft.ico": ("ico", "ICO", [], FormatOptions()),
        "com.apple.icns": ("icns", "ICNS", [], FormatOptions()),
        "com.ilm.openexr-image": ("exr", "OpenEXR", [], FormatOptions()),
        "com.microsoft.bmp": ("bmp", "BMP", [], FormatOptions()),
    ]

    public static let writable: [OutputFormat] = {
        var formats: [OutputFormat] = []
        for identifier in CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [] where !hidden.contains(identifier) {
            if identifier == UTType.pdf.identifier {
                formats.append(OutputFormat(id: "pdf", name: "PDF", fileExtension: "pdf", writer: .pdf,
                                            optionFields: [.lossless, .quality],
                                            defaultOptions: FormatOptions().with { $0.quality = 95 }))
            } else if let k = known[identifier] {
                formats.append(OutputFormat(id: k.id, name: k.name, fileExtension: k.id, writer: .imageIO(identifier),
                                            optionFields: k.fields, defaultOptions: k.defaults))
            } else {
                // A type a newer macOS added: written with no options.
                let ext = UTType(identifier)?.preferredFilenameExtension ?? identifier
                formats.append(OutputFormat(id: ext, name: ext.uppercased(), fileExtension: ext,
                                            writer: .imageIO(identifier), optionFields: [], defaultOptions: FormatOptions()))
            }
        }
        for (id, name, writer) in [("pbm", "PBM", OutputFormat.Writer.pbm), ("pgm", "PGM", .pgm), ("ppm", "PPM", .ppm),
                                   ("qoi", "QOI", .qoi), ("pcx", "PCX", .pcx)] {
            formats.append(OutputFormat(id: id, name: name, fileExtension: id, writer: writer,
                                        optionFields: [], defaultOptions: FormatOptions()))
        }
        formats.append(OutputFormat(id: "webp", name: "WebP", fileExtension: "webp", writer: .webp,
                                    optionFields: [.webpKind, .lossless, .quality, .effort],
                                    defaultOptions: FormatOptions().with { $0.quality = 75 }))
        formats.append(OutputFormat(id: "jxl", name: "JPEG XL", fileExtension: "jxl", writer: .jxl,
                                    optionFields: [.lossless, .quality, .effort, .keepMetadata],
                                    defaultOptions: FormatOptions().with { $0.quality = 90; $0.effort = 7 }))
        return formats.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    public static func format(id: String) -> OutputFormat? { writable.first { $0.id == id } }

    /// Names of every readable format, for the About window: ImageIO's (by preferred extension) then ours.
    public static var readableNames: (macOS: [String], own: [String]) {
        let macOS = Set((CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap {
            UTType($0)?.preferredFilenameExtension?.uppercased()
        })
        return (macOS.sorted(), OwnDecoders.all.map(\.name).sorted())
    }
}

public extension OutputFormat {
    // The four formats of milestone 1, which every Mac since 10.13 writes.
    static let jpeg = FormatRegistry.format(id: "jpg")!
    static let png = FormatRegistry.format(id: "png")!
    static let heic = FormatRegistry.format(id: "heic")!
    static let tiff = FormatRegistry.format(id: "tiff")!
}
