import AppKit
import FeatherviewCore
import QuickLookUI

/// Quick Look (Space) for the formats only Featherview reads (spec "Formats", Finder previews).
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let (screens, scale) = await MainActor.run {
            (NSScreen.screens.map { screen in
                PixelSize(width: Int((screen.frame.width * screen.backingScaleFactor).rounded()),
                          height: Int((screen.frame.height * screen.backingScaleFactor).rounded()))
            }, NSScreen.screens.map(\.backingScaleFactor).max() ?? 1)
        }
        let image = try QuickLookSupport.preview(request.fileURL, screens: screens)
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return QLPreviewReply(contextSize: size, isBitmap: true) { context, _ in
            context.draw(image, in: context.boundingBoxOfClipPath)
        }
    }
}
