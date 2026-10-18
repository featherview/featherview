/// When the viewer's toolbar and status strip hide while viewing (spec "Look").
/// Pure: the app feeds it pointer, key and timer events and sends `.tick` at `hideAt`.
public struct BarsAutoHide: Sendable, Equatable {
    /// Seconds without activity before the bars hide.
    public static let rest: Double = 2

    public enum Event: Sendable, Equatable {
        case enabled(Bool), fullScreen(Bool), panelOpen(Bool), windowKey(Bool)
        /// The pointer is off the picture: over the bars, or outside the window.
        case pointerOverBars(Bool)
        case pointerMoved, pointerAtTopEdge
        /// `browsing`: ← → Space ⌫ Page Up/Down Home End, which keep hidden bars hidden.
        case key(browsing: Bool)
        case tick
    }

    public private(set) var barsVisible = true
    /// When the caller should send `.tick`; nil = no timer.
    public var hideAt: Double?

    private var enabled = false
    private var fullScreen = false
    private var panelOpen = false
    private var windowKey = false
    /// Until a hover says otherwise: the bars hide only once the pointer rests over the picture.
    private var overBars = true

    private var mayHide: Bool { enabled && windowKey && !fullScreen && !panelOpen && !overBars }

    public init() {}

    public mutating func handle(_ event: Event, now: Double) {
        switch event {
        case .enabled(let on): enabled = on
        case .fullScreen(let on): fullScreen = on
        case .panelOpen(let on): panelOpen = on
        case .windowKey(let on): windowKey = on
        case .pointerOverBars(let on): overBars = on
        case .pointerMoved, .pointerAtTopEdge, .key(browsing: false):
            barsVisible = true
        case .key(browsing: true):
            break
        case .tick:
            if let hideAt, now >= hideAt, mayHide {
                barsVisible = false
                self.hideAt = nil
            }
            return
        }
        guard mayHide else {
            barsVisible = true
            hideAt = nil
            return
        }
        hideAt = barsVisible ? now + Self.rest : nil
    }
}
