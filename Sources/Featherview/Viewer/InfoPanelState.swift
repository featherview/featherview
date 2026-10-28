import FeatherviewCore
import Observation

enum HistogramMode: Hashable {
    case luminance, rgb
}

/// What the info panel keeps for every image and every window until the app quits (never saved):
/// which groups are open and the histogram's mode.
@MainActor @Observable final class InfoPanelState {
    static let shared = InfoPanelState()

    var open: Set<InfoGroup> = [.camera, .location]
    var mode: HistogramMode = .luminance
    /// The focus ring shows only for focus the keyboard moved, as on the Mac; a click focuses without one.
    var ringShown = false
    /// Set just before the keyboard moves the focus, so the change that follows shows the ring.
    var keyboardMove = false
}
