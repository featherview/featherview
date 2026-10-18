import Foundation
import UniformTypeIdentifiers

/// Which image types Featherview offers to open by default (spec "Viewer › Default viewer").
/// Pure decisions; the app asks LaunchServices for handlers and sets them.
public enum DefaultViewer {
    /// Apps whose image types Featherview may take over: Preview.
    public static let replaceable: Set<String> = ["com.apple.Preview"]

    /// Every type Featherview reads: ImageIO's, plus the extensions of its own decoders.
    public static var readableTypes: [UTType] {
        ImageFormats.decodable + OwnDecoders.all.flatMap(\.extensions).compactMap { UTType(filenameExtension: $0) }
    }

    /// The types to make Featherview the default for: each of `types` whose current default
    /// (`handler`, a bundle identifier, nil = none) is replaceable or none, minus PDF and anything
    /// conforming to it, minus dynamic types (`dyn.`), minus Featherview's own (`ownID`), deduplicated,
    /// in the order given.
    public static func typesToClaim(_ types: [UTType], ownID: String, handler: (UTType) -> String?) -> [UTType] {
        var seen: Set<UTType> = []
        return types.filter { type in
            guard !type.conforms(to: .pdf), !type.identifier.hasPrefix("dyn."), seen.insert(type).inserted else { return false }
            guard let current = handler(type) else { return true }
            return current != ownID && replaceable.contains(current)
        }
    }

    /// Whether the launch offer shows: running from `/Applications` or `~/Applications` (`home`)
    /// directly, not translocated (`/AppTranslocation/` in the path) and not from a mounted volume;
    /// not offered before; and JPEG's default is replaceable or none.
    public static func shouldOffer(bundleURL: URL, home: URL, offeredBefore: Bool, jpegHandler: String?) -> Bool {
        guard !offeredBefore, jpegHandler.map(replaceable.contains) ?? true else { return false }
        let path = bundleURL.standardizedFileURL.path
        guard !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        let folder = bundleURL.standardizedFileURL.deletingLastPathComponent().path
        return folder == "/Applications" || folder == home.appendingPathComponent("Applications").standardizedFileURL.path
    }
}
