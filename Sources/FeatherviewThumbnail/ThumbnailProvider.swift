import FeatherviewCore
import QuickLookThumbnailing

/// Finder's thumbnails for the formats only Featherview reads (spec "Formats", Finder previews).
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let (image, size) = try QuickLookSupport.thumbnail(request.fileURL, maximum: request.maximumSize,
                                                               scale: request.scale)
            // The context is in pixels, not in the points of contextSize: fill all of it.
            handler(QLThumbnailReply(contextSize: size) { context in
                context.draw(image, in: context.boundingBoxOfClipPath)
                return true
            }, nil)
        } catch {
            handler(nil, error)
        }
    }
}
