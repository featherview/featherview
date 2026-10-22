import AppKit
import FeatherviewCore

/// Pans the two compare panes in step: the pane the user scrolls, drags, pinches or clicks leads, and the other's
/// clear area follows its centre (`CompareSync.followerCentre`). Only the leader's moves are passed on, so the two
/// scroll views never echo each other.
@MainActor
final class CompareLink: NSObject {
    var inStep: Bool
    /// The pane the user last moved; set through `lead`.
    private(set) var leader = CompareSession.Pane.first
    var onLeader: (CompareSession.Pane) -> Void = { _ in }
    private weak var first: NSScrollView?
    private weak var second: NSScrollView?
    /// Set while a follower is moved, so its bounds change isn't taken for the user's.
    private var applying = false

    init(inStep: Bool) {
        self.inStep = inStep
    }

    func register(_ scrollView: NSScrollView, as pane: CompareSession.Pane) {
        guard self.scrollView(pane) !== scrollView else { return }
        if let old = self.scrollView(pane) {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: old.contentView)
        }
        if pane == .first { first = scrollView } else { second = scrollView }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    /// The user moved `pane` (scroll, drag, pinch, click): it leads from now on.
    func lead(_ pane: CompareSession.Pane) {
        guard leader != pane else { return }
        leader = pane
        onLeader(pane)
    }

    /// Places `pane`'s clear area on the other pane's current clear-area centre.
    func follow(_ pane: CompareSession.Pane) {
        guard inStep, !applying, let follower = scrollView(pane), let leading = scrollView(pane.other),
              let followerDocument = follower.documentView, let leadingDocument = leading.documentView else { return }
        let visible = leading.clearRect
        let centre = CompareSync.followerCentre(CGPoint(x: visible.midX, y: visible.midY),
                                                leaderDrawn: leadingDocument.frame.size,
                                                followerDrawn: followerDocument.frame.size)
        let clear = follower.clearRect.size
        applying = true
        defer { applying = false }
        moveVisibleOrigin(follower, to: CGPoint(x: centre.x - clear.width / 2, y: centre.y - clear.height / 2))
    }

    /// After a pane's resize: the follower lines up again, whichever pane SwiftUI updated first.
    func resized(_ pane: CompareSession.Pane) {
        follow(pane == leader ? pane.other : pane)
    }

    @objc private func boundsChanged(_ notification: Notification) {
        guard inStep, !applying, let clip = notification.object as? NSClipView,
              clip === scrollView(leader)?.contentView else { return }
        follow(leader.other)
    }

    private func scrollView(_ pane: CompareSession.Pane) -> NSScrollView? {
        pane == .first ? first : second
    }
}

extension CompareSession.Pane {
    var other: Self { self == .first ? .second : .first }
}
