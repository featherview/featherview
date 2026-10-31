import Foundation

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
