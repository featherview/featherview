/// Which frame of an animation shows and whether it plays. Pure: the app's player drives it.
public struct Playback: Equatable, Sendable {
    public private(set) var frame = 0
    public private(set) var isPlaying: Bool
    public let frameCount: Int

    public init(frameCount: Int, playing: Bool) {
        self.frameCount = frameCount
        isPlaying = playing
    }

    /// The next frame, the last one wrapping to the first.
    public mutating func advance() {
        frame = (frame + 1) % frameCount
    }

    public mutating func togglePlaying() {
        isPlaying.toggle()
    }

    /// One frame on or back, pausing even when it can't move: nothing past either end, as pages.
    @discardableResult public mutating func step(forward: Bool) -> Bool {
        isPlaying = false
        let next = frame + (forward ? 1 : -1)
        guard next >= 0, next < frameCount else { return false }
        frame = next
        return true
    }
}

/// Which decoded frames an animation keeps in memory.
public enum FrameStore {
    /// All frames are kept while they fit in this many bytes.
    public static let budget = 64 << 20

    public static func keepsAll(frameBytes: Int, count: Int) -> Bool {
        let (total, overflow) = frameBytes.multipliedReportingOverflow(by: count)
        return !overflow && total <= budget
    }

    /// The frames to have decoded, in the order they're due: every frame from `shown` on when all are
    /// kept, else `shown` and the next two; wrapping, no duplicates.
    public static func wanted(shown: Int, count: Int, keepsAll: Bool) -> [Int] {
        (0..<(keepsAll ? count : min(3, count))).map { (shown + $0) % count }
    }
}
