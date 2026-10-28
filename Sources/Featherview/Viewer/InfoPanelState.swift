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
}
