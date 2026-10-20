import AppKit
import FeatherviewCore
import QuickLookUI

/// Quick Look (Space) for the formats only Featherview reads (spec "Formats", Finder previews).
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let (screens, largest) = await MainActor.run {
            (NSScreen.screens.map { screen in
                PixelSize(width: Int((screen.frame.width * screen.backingScaleFactor).rounded()),
                          height: Int((screen.frame.height * screen.backingScaleFactor).rounded()))
            }, NSScreen.screens.map(\.frame.size).max { $0.width * $0.height < $1.width * $1.height })
        }
        let image = try QuickLookSupport.preview(request.fileURL, screens: screens)
        // One point per pixel, shrunk to fit the screen, as Quick Look shows a PNG; Retina draws it sharp at 2×.
        let size = QuickLookSupport.thumbnailSize(image: CGSize(width: image.width, height: image.height),
                                                  maximum: largest ?? CGSize(width: QuickLookSupport.fallbackScreen.width / 2,
                                                                            height: QuickLookSupport.fallbackScreen.height / 2))
        return QLPreviewReply(contextSize: size, isBitmap: true) { context, _ in
            context.draw(image, in: context.boundingBoxOfClipPath)
        }
    }
}
