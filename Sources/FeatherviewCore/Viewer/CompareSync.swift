import CoreGraphics

/// Zoom and pan of the second compare pane, matched to the first: the second picture is scaled to
/// cover the box the first is drawn in, centred, so the same detail sits at the same place in both.
/// Sizes are displayed (orientation-applied) pixel sizes.
public enum CompareSync {
    /// How much larger the second picture is drawn than the first at the same factor; 1 when either size is empty.
    public static func scale(first: CGSize, second: CGSize) -> Double {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0 else { return 1 }
        return min(first.width / second.width, first.height / second.height)
    }

    /// The second pane's zoom factor for the first pane's `firstFactor`.
    public static func matchedFactor(_ firstFactor: Double, first: CGSize, second: CGSize) -> Double {
        // shortcut: at the clamp the panes stop lining up, clamp pane 1's zoom to the pair's range if people zoom that far
        min(max(firstFactor * scale(first: first, second: second), ZoomSteps.range.lowerBound), ZoomSteps.range.upperBound)
    }

    /// The leader's clear-area centre in its document (points) mapped to the follower's: both
    /// pictures are centred in one box, so they differ by half the difference of their drawn sizes.
    public static func followerCentre(_ leaderCentre: CGPoint, leaderDrawn: CGSize, followerDrawn: CGSize) -> CGPoint {
        CGPoint(x: leaderCentre.x + (followerDrawn.width - leaderDrawn.width) / 2,
                y: leaderCentre.y + (followerDrawn.height - leaderDrawn.height) / 2)
    }
}
