import AppKit
import FeatherviewCore
import ObjectiveC

/// Asks before a window with an unsaved clipboard image closes. Wraps the window's own (SwiftUI's) delegate, like
/// `MenuKeys`'s menu proxy, and forwards everything else to it.
final class CloseGuard: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?  // SwiftUI keeps it alive; strong would cycle via the window
    private weak var model: ViewerModel?
    nonisolated(unsafe) private static var key = 0  // only its address is used, as the associated-object key; never read or written

    private init(_ original: NSWindowDelegate?, model: ViewerModel) {
        self.original = original
        self.model = model
    }

    @MainActor
    static func install(on window: NSWindow, model: ViewerModel) {
        guard !(window.delegate is CloseGuard) else { return }
        let proxy = CloseGuard(window.delegate, model: model)
        // The delegate is weak: the window keeps the proxy.
        objc_setAssociatedObject(window, &key, proxy, .OBJC_ASSOCIATION_RETAIN)
        window.delegate = proxy
    }

    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? { original }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.unsaved != nil else { return original?.windowShouldClose?(sender) ?? true }
        Task {
            guard await model.confirmDiscard() else { return }
            model.show()  // the covered image, for a reopened window
            sender.close()
        }
        return false
    }
}
