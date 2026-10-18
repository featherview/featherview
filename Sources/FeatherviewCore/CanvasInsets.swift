import CoreGraphics

/// How far fit keeps the image from the window's top and bottom edges: the canvas runs under the
/// toolbar and the floating status strip, but a fit image stays clear of both (spec "Viewer").
/// Auto-hiding bars only fade, they stay laid out, so there is no auto-hide input: fit never moves when they fade.
public struct CanvasInsets: Equatable, Sendable {
    public var top: Double
    public var bottom: Double

    public static let stripHeight = 22.0
    public static let stripMargin = 8.0

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }

    /// `toolbarHeight` is the window's top safe-area inset (title bar and toolbar; smaller when the toolbar is hidden).
    public static func make(toolbarHeight: Double, statusBarShown: Bool, fullScreen: Bool) -> CanvasInsets {
        if fullScreen { return CanvasInsets(top: 0, bottom: 0) }
        return CanvasInsets(top: toolbarHeight, bottom: statusBarShown ? stripHeight + 2 * stripMargin : 0)
    }

    /// The window area a fit image fills.
    public func fitArea(in window: CGSize) -> CGSize {
        CGSize(width: window.width, height: max(0, window.height - top - bottom))
    }
}
