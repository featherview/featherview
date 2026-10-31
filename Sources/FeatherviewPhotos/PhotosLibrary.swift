import AppKit
import FeatherviewCore
import Foundation
import os
import Photos

/// The Photos library through PhotoKit, for `featherview-photos:` URLs. Only local identifiers and URLs cross
/// actors; PhotoKit objects stay inside each call. Nothing here runs before the person first uses the library.
public final class PhotosLibrary: LibraryImages, @unchecked Sendable {
    public static let shared = PhotosLibrary()

    private struct State: Sendable {
        var names: [URL: String] = [:]
        var inCloud: Set<URL> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let manager = PHCachingImageManager()

    public init() {}

    // MARK: - Access

    /// Read and write access; the system prompt appears only while it is not determined.
    public func authorize() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .notDetermined else { return status }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Add-only access, for the batch destination.
    public func authorizeAdding() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        return status == .authorized || status == .limited
    }

    // MARK: - Pictures

    /// The asset behind `url`; a denied library or a deleted picture is one bad file.
    func asset(_ url: URL) throws -> PHAsset {
        guard let id = PhotosLocation.asset(of: url),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        else { throw DecodeError.unreadable(url) }
        return asset
    }

    /// The original file name ("IMG_1234.HEIC"), for the title and visible grid cells.
    public func name(_ url: URL) -> String {
        if let name = state.withLock({ $0.names[url] }) { return name }
        guard let asset = try? asset(url), let name = Self.originalName(of: asset) else {
            return PhotosLocation.asset(of: url) ?? url.lastPathComponent
        }
        state.withLock { $0.names[url] = name }
        return name
    }

    /// Whether the last `image` call for `url` got only Photos' local preview of a picture kept in iCloud.
    public func isInCloud(_ url: URL) -> Bool {
        state.withLock { $0.inCloud.contains(url) }
    }

    public func image(_ url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws -> CGImage {
        let asset = try asset(url)
        let side: Int
        switch target {
        case .fit(let screens):
            side = ImageDecoder.fitDecodeSize(image: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight),
                                              screens: screens)
        case .thumbnail(let thumbnail): side = thumbnail
        case .full, .step: throw DecodeError.unreadable(url)  // ImageDecoder decodes these from `file(_:)`
        }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        // A square target with aspect fit: the longest side becomes `side`.
        let size = CGSize(width: side, height: side)
        let (local, inCloud) = request(asset, size: size, options: options)
        var image = local
        if image == nil, inCloud {
            // Only in iCloud: Photos' local preview now, `download` brings the original.
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            image = request(asset, size: size, options: options).image
        }
        state.withLock { PhotosFetch.record(inCloud: inCloud, url, target: target, in: &$0.inCloud) }
        guard let image else { throw DecodeError.unreadable(url) }
        return ImageDecoder.inColorSpace(image, colorSpace)
    }

    /// A synchronous request: its handler has run when it returns.
    private func request(_ asset: PHAsset, size: CGSize, options: PHImageRequestOptions) -> (image: CGImage?, inCloud: Bool) {
        var result: (CGImage?, Bool) = (nil, false)
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
            result = (image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      (info?[PHImageResultIsInCloudKey] as? Bool) ?? false)
        }
        return result
    }

    /// Fetches the original from iCloud, so the next `image` call is local.
    public func download(_ url: URL) async throws {
        let asset = try asset(url)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        let ok = await withCheckedContinuation { continuation in
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data != nil)
            }
        }
        guard ok else { throw DecodeError.unreadable(url) }
        state.withLock { _ = $0.inCloud.remove(url) }
    }

    public func info(_ url: URL) -> FileInfo {
        let asset = try? asset(url)
        return FileInfo(url: url, page: 0, pixelSize: asset.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) },
                        bytes: nil, modified: asset?.creationDate, values: [:])
    }

    /// The current version (edited, or the original) fetched into `PhotosFetch.folder`, under the original's
    /// name; reused until the picture changes in Photos.
    public func file(_ url: URL) throws -> URL {
        let asset = try asset(url)
        guard let resource = Self.resource(of: asset) else { throw DecodeError.unreadable(url) }
        let folder = PhotosFetch.folder(asset: asset.localIdentifier, modified: asset.modificationDate)
        let file = folder.appendingPathComponent(PhotosFetch.fileName(original: Self.originalName(of: asset),
                                                                      written: resource.originalFilename))
        let fm = FileManager.default
        PhotosFetch.use(folder)
        if fm.fileExists(atPath: file.path) { return file }
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw DecodeError.unreadable(url) }
        // Written under a temporary name and moved in, so a second caller never sees half a file.
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let done = DispatchSemaphore(value: 0)
        let failed = OSAllocatedUnfairLock(initialState: false)
        PHAssetResourceManager.default().writeData(for: resource, toFile: temporary, options: options) { error in
            failed.withLock { $0 = error != nil }
            done.signal()
        }
        done.wait()
        defer { try? fm.removeItem(at: temporary) }
        if failed.withLock({ $0 }) { throw DecodeError.unreadable(url) }
        guard PhotosFetch.moveIn(temporary, to: file) else { throw DecodeError.unreadable(url) }
        return file
    }

    /// The current version's resource: the edited full-size photo when there is one, else the original.
    private static func resource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .fullSizePhoto } ?? resources.first { $0.type == .photo } ?? resources.first
    }

    /// The camera's name ("IMG_1234.HEIC"): the original's, since an edited version is always "FullSizeRender".
    private static func originalName(of asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        return (resources.first { $0.type == .photo } ?? resources.first)?.originalFilename
    }

    // MARK: - Changes

    /// Moves the pictures to Photos' Recently Deleted, after the system's one confirmation.
    public func delete(_ urls: [URL]) async throws {
        let ids = urls.compactMap(PhotosLocation.asset(of:))
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    /// Adds `file` to the library as a new picture; the file stays where it is.
    public func add(_ file: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: options)
        }
    }

    /// Empties the fetched files and the drops' folders: at launch (`all` false) all but those this run already
    /// uses, at quit (`all` true) everything. See `PhotosFetch.emptyCaches`.
    public static func emptyCaches(all: Bool) {
        PhotosFetch.emptyCaches(all: all)
    }
}
