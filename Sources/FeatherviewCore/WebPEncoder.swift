import Foundation
import libwebp

/// The spec's WebP "preset": what kind of picture libwebp tunes its lossy encoder for.
public enum WebPPictureKind: String, Codable, Sendable, CaseIterable {
    case photo, picture, drawing, icon, text
}

/// WebP through libwebp (spec "Formats": the format ImageIO reads but can't write).
public enum WebPEncoder {
    /// WebP's limit on either side.
    public static let maxDimension = 16383

    /// `quality` 1...100 (lossy; for lossless it trades time for size), `effort` 0...6 (libwebp's
    /// method: higher is slower and smaller). Out-of-range values are clamped.
    public static func encode(_ image: RGBAImage, quality: Int, lossless: Bool, effort: Int,
                              kind: WebPPictureKind) throws -> Data {
        _ = warmUp
        return try encodeNow(image, quality: quality, lossless: lossless, effort: effort, kind: kind)
    }

    /// libwebp picks its CPU-specific code on the first encode; batch starts one per core at once,
    /// so that first encode happens once, alone (a static let runs exactly once, thread-safely).
    private static let warmUp: Void = {
        _ = try? encodeNow(RGBAImage(width: 1, height: 1), quality: 75, lossless: false, effort: 0, kind: .photo)
    }()

    private static func encodeNow(_ image: RGBAImage, quality: Int, lossless: Bool, effort: Int,
                                  kind: WebPPictureKind) throws -> Data {
        guard (1...maxDimension).contains(image.width), (1...maxDimension).contains(image.height)
        else { throw EncodeError.failed }
        var config = WebPConfig()
        guard WebPConfigPreset(&config, kind.preset, Float(min(max(quality, 1), 100))) != 0 else { throw EncodeError.failed }
        config.lossless = lossless ? 1 : 0
        config.method = Int32(min(max(effort, 0), 6))
        guard WebPValidateConfig(&config) != 0 else { throw EncodeError.failed }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw EncodeError.failed }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        picture.use_argb = 1  // lossless needs ARGB; lossy converts to YUV itself
        let imported = image.pixels.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { throw EncodeError.failed }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else { throw EncodeError.failed }
        return Data(bytes: bytes, count: writer.size)
    }
}

private extension WebPPictureKind {
    var preset: WebPPreset {
        switch self {
        case .photo: WEBP_PRESET_PHOTO
        case .picture: WEBP_PRESET_PICTURE
        case .drawing: WEBP_PRESET_DRAWING
        case .icon: WEBP_PRESET_ICON
        case .text: WEBP_PRESET_TEXT
        }
    }
}
