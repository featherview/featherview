import CoreGraphics

/// How far fit keeps the image from the window's edges: the canvas runs under the toolbar and the
/// floating status strip, but a fit image stays clear of both (docs/DESIGN.md "Window layout":
/// insets 16 / 60 / 16 / 44 under the 52 pt title bar).
/// Auto-hiding bars only fade, they stay laid out, so there is no auto-hide input: fit never moves when they fade.
public struct CanvasInsets: Equatable, Sendable {
    public var top: Double
    public var bottom: Double
    public var leading: Double
    public var trailing: Double

    public static let stripHeight = 28.0
    /// The strip's gap to the window's bottom edge.
    public static let stripMargin = 8.0
    /// The strip's gap to the window's side edges.
    public static let stripSideMargin = 12.0
    /// Between a fit picture and a bar above or below it.
    public static let clearance = 8.0
    /// Between a fit picture and a window edge without a bar.
    public static let side = 16.0
    /// The info panel's width and its gap to the window's trailing edge.
    public static let infoPanelWidth = 280.0
    public static let infoPanelMargin = 12.0
    /// How much of the trailing side an open info panel takes, its gap to the picture included.
    public static let infoPanelSpan = infoPanelMargin + infoPanelWidth + side

    public init(top: Double, bottom: Double, leading: Double = 0, trailing: Double = 0) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    /// `toolbarHeight` is the window's top safe-area inset (title bar and toolbar; smaller when the toolbar is hidden).
    /// `infoPanelShown`: the panel floats on the trailing side and the picture refits beside it.
    public static func make(toolbarHeight: Double, statusBarShown: Bool, fullScreen: Bool,
                            infoPanelShown: Bool = false) -> CanvasInsets {
        let panel = infoPanelShown ? infoPanelSpan : nil
        if fullScreen { return CanvasInsets(top: 0, bottom: 0, trailing: panel ?? 0) }
        return CanvasInsets(top: toolbarHeight + clearance,
                            bottom: statusBarShown ? stripHeight + stripMargin + clearance : side,
                            leading: side, trailing: panel ?? side)
    }

    /// How far the on-image error box sits from the window's bottom edge: above the glass strip, never on it.
    public var messageBottom: Double { bottom }

    /// The window area a fit image fills.
    public func fitArea(in window: CGSize) -> CGSize {
        CGSize(width: max(0, window.width - leading - trailing), height: max(0, window.height - top - bottom))
    }
}
