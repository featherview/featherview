import FeatherviewCore
import CoreGraphics
import Foundation
import Observation

/// The second compare pane: one more file beside the viewer's current image. Exists only while comparing.
@MainActor @Observable
final class CompareSession {
    enum Pane { case first, second }

    /// The file pane 2 shows (or is about to: `image` and `info` change together when its decode lands).
    private(set) var url: URL
    var image: CGImage?
    /// `image`'s file details, set with it.
    var info: FileInfo?
    var errorMessage: String?
    /// The pane the user last scrolled, dragged, pinched or clicked; the other follows it.
    var leader: Pane = .first
    /// Pane 2's own zoom while not in step.
    var ownZoom: ViewerModel.Zoom = .fit
    var showsDifference = false
    var difference: CGImage?
    /// Pane 2's decode beyond fit size: one image, on the viewer's queue, gone when comparing ends.
    let zoomCache: ImageCache
    /// The decode asked for last, so asking again for the same one decodes nothing.
    @ObservationIgnored var wanted: (url: URL, target: DecodeTarget)?
    @ObservationIgnored var task: Task<Void, Never>?

    init(url: URL, zoomCache: ImageCache) {
        self.url = url
        self.zoomCache = zoomCache
    }

    /// Pane 2 changes file; its picture stays until the new one is decoded.
    func change(to url: URL) {
        self.url = url
        errorMessage = nil
        wanted = nil
    }
}
