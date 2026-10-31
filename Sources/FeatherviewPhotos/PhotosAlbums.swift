import FeatherviewCore
import Foundation
import Photos

extension PhotosLibrary {
    /// Whether a system smart album of this subtype is listed under Media Types (when it holds pictures): every one
    /// but the video, hidden and generic ones and those the sheet lists elsewhere or that aren't media types.
    static func isMediaType(_ subtype: PHAssetCollectionSubtype) -> Bool {
        ![.smartAlbumVideos, .smartAlbumSlomoVideos, .smartAlbumTimelapses, .smartAlbumCinematic, .smartAlbumScreenRecordings,
          .smartAlbumAllHidden, .smartAlbumGeneric, .smartAlbumFavorites, .smartAlbumRecentlyAdded, .smartAlbumUserLibrary,
          .smartAlbumUnableToUpload].contains(subtype)
    }

    /// The sheet's rows: Library, Favorites, Recents, the media types that hold pictures, then the person's albums
    /// depth-first with their folder path. Counts come later (`count`).
    public func albums() async -> [PhotosAlbumRow] {
        var rows = [PhotosAlbumRow(id: "library", name: String(localized: "Library", comment: "Open from Photos sheet: all pictures"),
                                   folders: [], kind: .library, count: nil)]
        for (subtype, kind, name) in [
            (PHAssetCollectionSubtype.smartAlbumFavorites, PhotosAlbumKind.favorites,
             String(localized: "Favorites", comment: "Open from Photos sheet: the Favorites album")),
            (.smartAlbumRecentlyAdded, .recents, String(localized: "Recents", comment: "Open from Photos sheet: the Recents album")),
        ] {
            if let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).firstObject {
                rows.append(PhotosAlbumRow(id: album.localIdentifier, name: name, folders: [], kind: kind, count: nil))
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil).enumerateObjects { album, _, _ in
            let probe = Self.imagesOnly(sorted: false)
            probe.fetchLimit = 1
            guard Self.isMediaType(album.assetCollectionSubtype),
                  PHAsset.fetchAssets(in: album, options: probe).count > 0 else { return }
            rows.append(PhotosAlbumRow(id: album.localIdentifier, name: album.localizedTitle ?? "", folders: [],
                                       kind: .mediaType, count: nil))
        }
        func walk(_ collections: PHFetchResult<PHCollection>, folders: [String]) {
            collections.enumerateObjects { collection, _, _ in
                if let album = collection as? PHAssetCollection, album.assetCollectionSubtype != .albumCloudShared {
                    rows.append(PhotosAlbumRow(id: album.localIdentifier, name: album.localizedTitle ?? "",
                                               folders: folders, kind: .userAlbum, count: nil))
                } else if let folder = collection as? PHCollectionList {
                    walk(PHCollection.fetchCollections(in: folder, options: nil), folders: folders + [folder.localizedTitle ?? ""])
                }
            }
        }
        walk(PHCollectionList.fetchTopLevelUserCollections(with: nil), folders: [])
        return rows
    }

    /// How many pictures the album holds (videos left out).
    public func count(_ album: String) async -> Int {
        (try? fetch(album, sorted: false).assets.count) ?? 0  // the order doesn't change the count
    }

    /// The album's pictures in its own order (Library, Favorites, Recents and media types by date taken, oldest
    /// first), as URLs; only identifiers are read per asset.
    public func list(_ album: String) async throws -> (urls: [URL], kind: PhotosAlbumKind) {
        let (assets, kind) = try fetch(album)
        state.withLock { $0.names.forgetFailures() }
        // One batch read: enumerateObjects is about 13 times slower (78 ms against 6 ms for 3,700 pictures).
        let urls = assets.objects(at: IndexSet(integersIn: 0..<assets.count))
            .map { PhotosLocation.url(album: album, asset: $0.localIdentifier) }
        return (urls, kind)
    }

    private func fetch(_ album: String, sorted: Bool = true) throws -> (assets: PHFetchResult<PHAsset>, kind: PhotosAlbumKind) {
        if album == "library" { return (PHAsset.fetchAssets(with: Self.imagesOnly(sorted: sorted)), .library) }
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album], options: nil).firstObject
        else { throw DecodeError.unreadable(PhotosLocation.albumURL(album)) }
        let kind: PhotosAlbumKind = switch collection.assetCollectionSubtype {
        case .smartAlbumFavorites: .favorites
        case .smartAlbumRecentlyAdded: .recents
        case let subtype where collection.assetCollectionType == .smartAlbum && Self.isMediaType(subtype): .mediaType
        default: .userAlbum
        }
        return (PHAsset.fetchAssets(in: collection, options: Self.imagesOnly(sorted: sorted && kind != .userAlbum)), kind)
    }

    /// Pictures only; `sorted`: by date taken, oldest first, else the album's own order.
    private static func imagesOnly(sorted: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        if sorted { options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)] }
        return options
    }
}
