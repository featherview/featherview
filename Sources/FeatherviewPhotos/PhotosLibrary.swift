import AppKit
import FeatherviewCore
import Foundation
import os
import Photos

/// The Photos library through PhotoKit, for `featherview-photos:` URLs. Only local identifiers and URLs cross
/// actors; PhotoKit objects stay inside each call. Nothing here runs before the person first uses the library.
public final class PhotosLibrary: LibraryImages, @unchecked Sendable {
    public static let shared = PhotosLibrary()

    struct State: Sendable {
        var names = PhotosNames()
        var inCloud: Set<URL> = []
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    /// Made on the first picture, not at launch, where the app makes `shared`.
    private let madeManager = OSAllocatedUnfairLock<PHCachingImageManager?>(uncheckedState: nil)

    private var manager: PHCachingImageManager {
        madeManager.withLockUnchecked { made in
            if let made { return made }
            let manager = PHCachingImageManager()
            made = manager
            return manager
        }
    }

    var hasImageManager: Bool { madeManager.withLockUnchecked { $0 != nil } }

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

    /// The asset behind `url`; a denied library or a deleted picture is one bad file. Its name is noted on the way,
    /// so a picture decoded (or prefetched) is named even after it is gone.
    func asset(_ url: URL) throws -> PHAsset {
        guard let id = PhotosLocation.asset(of: url),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        else {
            state.withLock { if $0.names.lookup(url) == .unknown { $0.names.record(nil, for: url) } }
            throw DecodeError.unreadable(url)
        }
        if state.withLock({ $0.names.lookup(url) }) == .unknown {
            let name = Self.originalName(of: asset)
            state.withLock { $0.names.record(name, for: url) }
        }
        return asset
    }

    /// The original file name ("IMG_1234.HEIC") as far as looked up; no PhotoKit call, so fine on the main thread.
    public func knownName(_ url: URL) -> PhotosNames.Lookup {
        state.withLock { $0.names.lookup(url) }
    }

    /// Looks up the names of those of `urls` not looked up yet, in one fetch; off the main thread.
    public func lookUpNames(_ urls: [URL]) {
        let missing = state.withLock { $0.names.missing(urls) }
        guard !missing.isEmpty else { return }
        var found: [String: String] = [:]
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: missing.compactMap(PhotosLocation.asset(of:)), options: nil)
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            found[asset.localIdentifier] = Self.originalName(of: asset)
        }
        let named = missing.map { url in (url, PhotosLocation.asset(of: url).flatMap { found[$0] }) }
        state.withLock { state in
            for (url, name) in named { state.names.record(name, for: url) }
        }
    }

    /// The original file name, looked up now if need be; nil when it can't be.
    public func name(_ url: URL) -> String? {
        lookUpNames([url])
        if case .found(let name) = knownName(url) { return name }
        return nil
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
            // Only in iCloud: the largest picture Photos keeps locally now (the grid gets up to 512 px this way;
            // `.fastFormat` alone can be a 60 px one), `download` brings the original.
            image = [2048, 1024, 512].lazy.filter { $0 < side }
                .compactMap { self.request(asset, size: CGSize(width: $0, height: $0), options: options).image }.first
            if image == nil {
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                image = request(asset, size: size, options: options).image
            }
            image = image.map { ImageDecoder.enlarged($0, toLongestSide: side) }
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

    /// Fetches the original from iCloud, so the next `image` call is local. Cancelling the task stops the download
    /// and throws `CancellationError`.
    public func download(_ url: URL) async throws {
        let asset = try asset(url)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        let manager = manager
        let request = OSAllocatedUnfairLock<PHImageRequestID?>(initialState: nil)
        let ok = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // PhotoKit calls the handler also for a cancelled request, without data.
                let id = manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: data != nil)
                }
                request.withLock { $0 = id }
                if Task.isCancelled { manager.cancelImageRequest(id) }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelImageRequest(id) }
        }
        try Task.checkCancellation()
        guard ok else { throw DecodeError.unreadable(url) }
        state.withLock { _ = $0.inCloud.remove(url) }
    }

    public func info(_ url: URL) -> FileInfo {
        let asset = try? asset(url)
        return FileInfo(url: url, page: 0, pixelSize: asset.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) },
                        bytes: nil, modified: asset?.creationDate, values: [:])
    }

    /// The current version (edited, or the original) fetched into `PhotosFetch.folder`, under the original's
    /// name; reused until the picture changes in Photos. Without `network`, an original only in iCloud fails.
    public func file(_ url: URL) throws -> URL { try file(url, network: true) }

    public func file(_ url: URL, network: Bool) throws -> URL {
        let asset = try asset(url)
        let resources = Self.resources(of: asset)
        guard let resource = resources.current else { throw DecodeError.unreadable(url) }
        let folder = PhotosFetch.folder(asset: asset.localIdentifier, modified: asset.modificationDate)
        let file = folder.appendingPathComponent(PhotosFetch.fileName(original: resources.originalName,
                                                                      written: resource.originalFilename))
        let fm = FileManager.default
        PhotosFetch.use(folder)
        if fm.fileExists(atPath: file.path) { return file }
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw DecodeError.unreadable(url) }
        // Written under a temporary name and moved in, so a second caller never sees half a file.
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = network
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

    /// From one lookup of the asset's resources: the current version's (the edited full-size photo when there is
    /// one, else the original) and the camera's name ("IMG_1234.HEIC"), the original's, since an edited version is
    /// always "FullSizeRender".
    private static func resources(of asset: PHAsset) -> (current: PHAssetResource?, originalName: String?) {
        let resources = PHAssetResource.assetResources(for: asset)
        let original = resources.first { $0.type == .photo } ?? resources.first
        return (resources.first { $0.type == .fullSizePhoto } ?? original, original?.originalFilename)
    }

    private static func originalName(of asset: PHAsset) -> String? { resources(of: asset).originalName }

    // MARK: - Changes

    /// Moves the pictures to Photos' Recently Deleted, after the system's one confirmation.
    public func delete(_ urls: [URL]) async throws {
        let ids = urls.compactMap(PhotosLocation.asset(of:))
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    /// The person's Cancel in Photos' delete prompt, which needs no message.
    public static func isCancel(_ error: Error) -> Bool {
        (error as? PHPhotosError)?.code == .userCancelled
    }

    /// Adds `file` to the library as a new picture; the file stays where it is.
    public func add(_ file: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: options)
        }
    }
}
