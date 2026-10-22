import Foundation
import ImageIO

/// An animated image's frame delays (spec "Animation"); nil from `read` for anything that doesn't animate.
public struct Animation: Equatable, Sendable {
    public let delays: [Duration]
    public var frameCount: Int { delays.count }

    /// The animation types: their top-level dictionary and the keys inside it. AVIF sequences use HEICS's keys.
    private static var kinds: [(dictionary: CFString, frames: CFString, unclamped: CFString, clamped: CFString)] { [
        (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFFrameInfoArray,
         kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
        (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGFrameInfoArray,
         kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPFrameInfoArray,
         kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSFrameInfoArray,
         kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        (kCGImagePropertyAVISDictionary, kCGImagePropertyHEICSFrameInfoArray,
         kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
    ] }

    /// Nil for a still, a single frame, an unreadable file, a multi-page TIFF or a HEIC collection.
    public static func read(_ url: URL) -> Animation? {
        if let own = OwnDecoders.format(for: url) {
            guard let delays = own.delays, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let seconds = delays(data), seconds.count > 1 else { return nil }
            return Animation(delays: seconds.map { delay(seconds: $0) })
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let kind = kinds.first(where: { properties[$0.dictionary] != nil }) else { return nil }
        // APNG's and HEICS's frame info lacks the unclamped delay; per-frame properties always have it.
        let info = (properties[kind.dictionary] as? [CFString: Any])?[kind.frames] as? [[CFString: Any]]
        let fromInfo = info?.compactMap { $0[kind.unclamped] as? Double }
        let seconds: [Double?] = fromInfo?.count == count ? fromInfo! : (0..<count).map { index in
            let frame = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kind.dictionary]
                as? [CFString: Any]
            return frame?[kind.unclamped] as? Double ?? frame?[kind.clamped] as? Double
        }
        return Animation(delays: seconds.map { delay(seconds: $0) })
    }

    /// The browsers' rule: no delay, or 10 ms or less, plays at 100 ms.
    static func delay(seconds: Double?) -> Duration {
        guard let seconds, seconds > 0.01 else { return .milliseconds(100) }
        return .milliseconds((seconds * 1000).rounded())
    }
}
