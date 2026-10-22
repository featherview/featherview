import CoreGraphics
import Foundation
import ImageIO

/// An animation's frames at the viewer's decode target, the same size, orientation, depth and colour space
/// as `ImageDecoder.decode` gives frame 0 for that target (SDR only: animations have no HDR).
/// The file is opened once and kept: ImageIO composites delta frames from the frames before, so asking
/// in order from one source is fast (0.8 ms per 400×300 frame) where a fresh source pays for every earlier frame.
public actor FrameSource {
    private let reader: FrameReader

    /// Throws `DecodeError.unreadable` if the file isn't a readable image.
    public init(url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws {
        reader = try FrameReader(url: url, target: target, colorSpace: colorSpace)
    }

    /// Frame `index`, decoded now. Throws `DecodeError.unreadable` for a frame past the end or one the
    /// file doesn't fully hold (a truncated download).
    public func frame(_ index: Int) throws -> CGImage { try reader.frame(index) }
}

/// `FrameSource`'s work on the caller's thread, for code already off the main thread (the batch). One thread at a time.
public final class FrameReader {
    private enum File {
        case imageIO(CGImageSource, count: Int)
        case own(OwnFormat, Data)
    }

    private let url: URL
    private let file: File
    private let limit: Int?
    private let colorSpace: CGColorSpace?

    /// Throws `DecodeError.unreadable` if the file isn't a readable image.
    public init(url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws {
        self.url = url
        self.colorSpace = colorSpace
        let screens: [PixelSize]? = if case .fit(let screens) = target { screens } else { nil }
        let step: Int? = if case .step(let step) = target { step } else { nil }
        if let own = OwnDecoders.format(for: url) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw DecodeError.unreadable(url) }
            file = .own(own, data)
            limit = own.size(data, 0).flatMap { ImageDecoder.targetSize($0, screens: screens, step: step, exact: true) }
        } else {
            guard let size = ImageDecoder.displaySize(of: url),
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { throw DecodeError.unreadable(url) }
            file = .imageIO(source, count: CGImageSourceGetCount(source))
            limit = ImageDecoder.targetSize(size, screens: screens, step: step, exact: ImageDecoder.decodesAtExactFit(url))
                ?? Int(max(size.width, size.height))
        }
    }

    /// Frame `index`, decoded now. Throws `DecodeError.unreadable` for a frame past the end or one the
    /// file doesn't fully hold (a truncated download).
    public func frame(_ index: Int) throws -> CGImage {
        let image: CGImage
        switch file {
        case .own(let own, let data):
            do {
                let decoded = try own.decode(data, index, limit)
                image = limit.flatMap { ImageDecoder.scaled(decoded, longestSide: $0) } ?? decoded
            } catch {
                throw DecodeError.unreadable(url)
            }
        case .imageIO(let source, let count):
            guard index >= 0, index < count, CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                  let decoded = CGImageSourceCreateThumbnailAtIndex(
                      source, index, ImageDecoder.thumbnailOptions(maxPixelSize: limit ?? 0) as CFDictionary),
                  let eight = ImageDecoder.eightBit(decoded)
            else { throw DecodeError.unreadable(url) }
            image = eight
        }
        return ImageDecoder.inColorSpace(image, colorSpace)
    }
}
