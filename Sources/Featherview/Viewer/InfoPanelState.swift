import Observation

/// The info panel's groups, in the order the panel shows them.
enum InfoGroup: CaseIterable, Hashable {
    case camera, image, location, description, file
}

enum HistogramMode: Hashable {
    case luminance, rgb
}

/// What the info panel keeps for every image and every window until the app quits (never saved):
/// which groups are open and the histogram's mode.
@MainActor @Observable final class InfoPanelState {
    static let shared = InfoPanelState()

    var open: Set<InfoGroup> = [.camera, .location]
    var mode: HistogramMode = .luminance
    /// "Show all metadata…": the All Metadata window sets it.
    var showAllMetadata: () -> Void = {}
}

/// The panel's keyboard stops, in Tab order (spec "Keyboard and accessibility").
enum InfoFocus: Hashable {
    case mode, shadowsClip, highlightsClip
    case header(InfoGroup)
    case button(InfoGroup)
    case showAll
}
