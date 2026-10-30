import CoreGraphics
import FeatherviewCore
import Foundation

/// A zoomed huge picture: the fit picture shows enlarged, a sharp decode of only the visible part lies over it.
extension ViewerModel {
    /// The canvas's visible rect, in full-size pixels: asks for a new part when none is there or panning nears
    /// the edge of the one decoded (or asked for).
    func visibleRectChanged(_ visible: CGRect) {
        lastVisible = visible
        guard let step = regionStep, let url = list.current, let size = shownStep?.size else { return }
        let image = PixelSize(width: Int(size.width), height: Int(size.height))
        if let decoded = regionRequest ?? region?.rect,
           !RegionZoom.needsNewRegion(visible: visible, decoded: decoded, image: image) { return }
        let rect = RegionZoom.region(visible: visible, image: image, step: step)
        guard !rect.isEmpty else { return }
        regionRequest = rect
        let space = screenSpace
        regionDecodes.submit { [weak self] in
            let signpost = Signposts.poster.beginInterval("RegionDecode", id: Signposts.poster.makeSignpostID(),
                                                          "\(url.lastPathComponent, privacy: .public)")
            // A failed part leaves the enlarged fit picture: the file opened, so no message.
            let part = try? await Task.detached(priority: .userInitiated) {
                try ImageDecoder.decodeRegion(url, region: rect, step: step, colorSpace: space)
            }.value
            Signposts.poster.endInterval("RegionDecode", signpost)
            // Another file, page or step, or a newer part asked for meanwhile: this one would land in the wrong place.
            guard let self, let part, list.current == url, regionStep == step, regionRequest == rect else { return }
            regionRequest = nil
            region = (part, rect)
        }
    }
}
