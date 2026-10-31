import CryptoKit
import Foundation
import os

/// A picture in the Photos library as a URL: `featherview-photos://library/<album>/<asset>`, each
/// identifier percent-encoded into one path component (its `/` as `%2F`). The album URL is the
/// picture's "folder", so lists, caches and the grid treat library pictures like files.
public enum PhotosLocation {
    public static let scheme = "featherview-photos"

    /// `album` is a `PHAssetCollection.localIdentifier` or `"library"`; `asset` a `PHAsset.localIdentifier`.
    public static func url(album: String, asset: String) -> URL {
        make("/\(encode(album))/\(encode(asset))")
    }

    /// The album's URL, with the trailing slash `deletingLastPathComponent()` leaves on a picture's URL.
    public static func albumURL(_ album: String) -> URL {
        make("/\(encode(album))/")
    }

    public static func album(of url: URL) -> String? {
        parts(url).first
    }

    public static func asset(of url: URL) -> String? {
        let parts = parts(url)
        return parts.count == 2 ? parts[1] : nil
    }

    /// The picture an album opens at: `keeping` while the album still has it, else its newest picture for
    /// Library, Recents and the media types, its first for the others.
    public static func start(_ urls: [URL], kind: PhotosAlbumKind, keeping: URL?) -> URL? {
        if let keeping, urls.contains(keeping) { return keeping }
        return kind.opensAtEnd ? urls.last : urls.first
    }

    /// By scheme only; never looks at the disk.
    public static func isLibrary(_ url: URL) -> Bool {
        url.scheme == scheme
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()

    private static func encode(_ identifier: String) -> String {
        identifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? identifier
    }

    private static func make(_ percentEncodedPath: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "library"
        components.percentEncodedPath = percentEncodedPath
        return components.url!
    }

    /// Split on the encoded path: `lastPathComponent` would decode `%2F` into extra components.
    private static func parts(_ url: URL) -> [String] {
        guard isLibrary(url),
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
        else { return [] }
        return path.split(separator: "/").compactMap { $0.removingPercentEncoding }
    }
}

public enum PhotosAlbumKind: Sendable {
    case library, favorites, recents, mediaType, userAlbum

    /// Opens at the newest picture (the last), as Photos opens these scrolled to the end.
    public var opensAtEnd: Bool {
        switch self {
        case .library, .recents, .mediaType: true
        case .favorites, .userAlbum: false
        }
    }
}

/// Library pictures' original file names, each looked up once; a failed lookup (deleted in Photos, access
/// revoked) is kept too, so it isn't asked again.
public struct PhotosNames: Sendable {
    public enum Lookup: Equatable, Sendable {
        case unknown, failed
        case found(String)
    }

    private var known: [URL: String?] = [:]

    public init() {}

    public func lookup(_ url: URL) -> Lookup {
        guard let name = known[url] else { return .unknown }
        return name.map(Lookup.found) ?? .failed
    }

    public mutating func record(_ name: String?, for url: URL) {
        known[url] = .some(name)
    }

    /// Those of `urls` not looked up yet.
    public func missing(_ urls: [URL]) -> [URL] {
        urls.filter { known[$0] == nil }
    }

    /// An album listed again: access may be back.
    public mutating func forgetFailures() {
        known = known.filter { $0.value != nil }
    }
}

/// One row of the Open from Photos sheet.
public struct PhotosAlbumRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The folders the album sits in, outermost first.
    public var folders: [String]
    public var kind: PhotosAlbumKind
    /// Filled in off the main thread; nil until counted.
    public var count: Int?

    public init(id: String, name: String, folders: [String], kind: PhotosAlbumKind, count: Int?) {
        self.id = id
        self.name = name
        self.folders = folders
        self.kind = kind
        self.count = count
    }
}

/// The Open from Photos sheet's layout.
public enum PhotosSheet {
    public struct Section: Equatable, Sendable {
        public var title: String?
        public var rows: [PhotosAlbumRow]

        public init(title: String?, rows: [PhotosAlbumRow]) {
            self.title = title
            self.rows = rows
        }
    }

    /// Library, Favorites, Recents (untitled), then Media Types, then My Albums in the given order;
    /// empty sections left out.
    public static func sections(_ rows: [PhotosAlbumRow]) -> [Section] {
        let top: [PhotosAlbumKind] = [.library, .favorites, .recents]
        let sections = [
            Section(title: nil, rows: top.flatMap { kind in rows.filter { $0.kind == kind } }),
            Section(title: String(localized: "Media Types", comment: "Open from Photos sheet: section of the system's smart albums"),
                    rows: rows.filter { $0.kind == .mediaType }),
            Section(title: String(localized: "My Albums", comment: "Open from Photos sheet: section of the person's albums"),
                    rows: rows.filter { $0.kind == .userAlbum }),
        ]
        return sections.filter { !$0.rows.isEmpty }
    }

    /// The album's folder path under its name ("Trips › 2025"), nil outside folders.
    public static func subtitle(_ row: PhotosAlbumRow) -> String? {
        row.folders.isEmpty ? nil : row.folders.joined(separator: " › ")
    }
}

/// The Photos library's texts that the app builds outside SwiftUI literals.
public enum PhotosText {
    public static var denied: String {
        String(localized: "Featherview can't see your Photos library.", comment: "Open from Photos sheet when access is denied")
    }

    public static var deniedHelp: String {
        String(localized: "Allow it in System Settings › Privacy & Security › Photos.",
               comment: "Open from Photos sheet when access is denied, under the first sentence")
    }

    public static var downloading: String {
        String(localized: "Downloading from iCloud…", comment: "Status bar while a library picture's original downloads")
    }

    public static func cantDownload(name: String) -> String {
        String(localized: "Can't download \(name) from iCloud.", comment: "Status bar when a library picture's original can't be downloaded")
    }

    public static var needsDestination: String {
        String(localized: "Choose where to save pictures from Photos.",
               comment: "Batch: Start with library pictures and Next to the originals")
    }

    public static func cantImport(format: String) -> String {
        String(localized: "Photos can't import \(format).", comment: "Batch: why the Photos library destination is off for a format")
    }

    public static func cantAdd(name: String) -> String {
        String(localized: "Can't add \(name) to Photos.", comment: "Batch log row when Photos refuses an output")
    }
}

/// How `PhotosLibrary` names, places and keeps track of library pictures, without PhotoKit.
public enum PhotosFetch {
    /// The fetched file's name: the original's base name ("IMG_1234") with the written resource's extension,
    /// since Photos names every edited version "FullSizeRender".
    public static func fileName(original: String?, written: String) -> String {
        guard let original else { return written }
        let ext = (written as NSString).pathExtension
        let base = (original as NSString).deletingPathExtension
        return ext.isEmpty ? original : "\(base).\(ext)"
    }

    /// One folder per asset and version, so two IMG_0001.HEIC never meet and an edit in Photos fetches anew.
    public static func folder(asset: String, modified: Date?) -> URL {
        let key = "\(asset)\n\(modified?.timeIntervalSinceReferenceDate ?? 0)"
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return BatchSettings.photosCache.appendingPathComponent(hash, isDirectory: true)
    }

    /// Only the fit request says whether the viewer shows a preview of an iCloud-only picture: a thumbnail
    /// Photos keeps locally says nothing about the original.
    public static func record(inCloud: Bool, _ url: URL, target: DecodeTarget, in set: inout Set<URL>) {
        guard case .fit = target else { return }
        if inCloud { set.insert(url) } else { set.remove(url) }
    }

    /// Moves a fetched file into place; true when `file` is there afterwards, also when another fetch of
    /// the same picture got there first.
    public static func moveIn(_ temporary: URL, to file: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) { try? fm.moveItem(at: temporary, to: file) }
        return fm.fileExists(atPath: file.path)
    }

    /// Cache folders (a drop's, a fetched picture's) this run uses; the launch-time emptying leaves them alone.
    /// Held while emptying, so a folder is either emptied before its first use or not at all.
    private static let used = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Marks `folder` as used by this run; waits while the launch-time emptying is on it. Call it before
    /// touching the folder, off the main thread.
    public static func use(_ folder: URL) {
        used.withLock { _ = $0.insert(folder.standardizedFileURL.path) }
    }

    /// Empties the fetched pictures in `photos` and the drops' folders in `dropped`; drops lose only the
    /// files Photos handed over (`DropItem.freshFolder`). Unless `all` (at quit), folders this run uses stay.
    public static func emptyCaches(photos: URL = BatchSettings.photosCache, dropped: URL = BatchSettings.droppedCache, all: Bool) {
        let fm = FileManager.default
        func each(_ root: URL, _ empty: (URL) -> Void) {
            for folder in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                used.withLockUnchecked { if all || !$0.contains(folder.standardizedFileURL.path) { empty(folder) } }
            }
        }
        if all { try? fm.removeItem(at: photos) } else { each(photos) { try? fm.removeItem(at: $0) } }
        each(dropped) { _ = DropItem.freshFolder($0) }
    }
}
