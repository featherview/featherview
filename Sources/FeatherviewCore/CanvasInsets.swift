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

    public init(top: Double, bottom: Double, leading: Double = 0, trailing: Double = 0) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    /// `toolbarHeight` is the window's top safe-area inset (title bar and toolbar; smaller when the toolbar is hidden).
    public static func make(toolbarHeight: Double, statusBarShown: Bool, fullScreen: Bool) -> CanvasInsets {
        if fullScreen { return CanvasInsets(top: 0, bottom: 0) }
        return CanvasInsets(top: toolbarHeight + clearance,
                            bottom: statusBarShown ? stripHeight + stripMargin + clearance : side,
                            leading: side, trailing: side)
    }

    /// How far the on-image error box sits from the window's bottom edge: above the glass strip, never on it.
    public var messageBottom: Double { bottom }

    /// The window area a fit image fills.
    public func fitArea(in window: CGSize) -> CGSize {
        CGSize(width: max(0, window.width - leading - trailing), height: max(0, window.height - top - bottom))
    }
}
