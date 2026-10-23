import Foundation
import UniformTypeIdentifiers

/// Which image types Featherview offers to open by default (spec "Viewer › Default viewer").
/// Pure decisions; the app asks LaunchServices for handlers and sets them.
public enum DefaultViewer {
    /// Apps whose image types Featherview may take over: Preview.
    public static let replaceable: Set<String> = ["com.apple.Preview"]

    /// The types Settings › Browsing lists, each with its own button. macOS asks once per type
    /// it hands to another app, so each click claims one type and costs at most one prompt.
    public static let commonTypes: [UTType] = [.jpeg, .png, .heic, .gif, .tiff, .webP]

    /// The type "Always Open with Featherview" claims for `file`, from its extension: nil for PDF and
    /// anything conforming to it (Featherview isn't a PDF reader) and for extensions macOS doesn't know.
    public static func claimableType(for file: URL) -> UTType? {
        guard let type = UTType(filenameExtension: file.pathExtension), !type.isDynamic, !type.conforms(to: .pdf) else { return nil }
        return type
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
