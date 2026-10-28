import AppKit
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
    /// The focus ring shows only for focus the keyboard moved, as on the Mac: a click hides it, and focus the
    /// window gets back on reactivation keeps it as it was.
    var ringShown = false
    /// Set just before the keyboard moves the focus, so the change that follows shows the ring.
    var keyboardMove = false

    private init() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated { InfoPanelState.shared.ringShown = false }
            return event
        }
    }
}
