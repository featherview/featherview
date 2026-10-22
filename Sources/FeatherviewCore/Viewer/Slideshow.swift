import Foundation

/// A slideshow's play order, position and timing. Time comes in as `now`, so nothing here sleeps.
/// The order is its own list of URLs (one round, plus the next one drawn ahead); the viewer's list
/// keeps Finder order.
public struct Slideshow: Equatable, Sendable {
    public struct Options: Equatable, Sendable {
        public var interval: Duration
        public var shuffle: Bool
        public var repeats: Bool

        public init(interval: Duration, shuffle: Bool, repeats: Bool) {
            self.interval = interval
            self.shuffle = shuffle
            self.repeats = repeats
        }
    }

    /// The choices of View › Slideshow Options › Show Each Image For, in seconds.
    public static let intervals: [Int] = [1, 2, 3, 5, 10, 20, 30, 60]

    public private(set) var options: Options
    public private(set) var isPaused = false
    public private(set) var isFinished = false
    public var isPlaying: Bool { !isPaused && !isFinished }
    /// When the image on screen gives way; nil while paused, finished or waiting for `current` to show.
    public private(set) var due: ContinuousClock.Instant?

    /// Every image still in the slideshow, Finder order.
    private var urls: [URL]
    private var round: [URL]
    private var position = 0
    /// The round after this one, drawn when this one starts (used with Repeat).
    private var nextRound: [URL] = []
    private var generator: SplitMix64
    private var forward = true
    /// The images that couldn't be shown since the last one that could.
    private var failedRun: Set<URL> = []
    /// `current` has been on screen, so resuming may start its interval.
    private var shownCurrent = false

    /// The first round plays from `current` (or the first image when it isn't listed).
    public init(urls: [URL], from current: URL, options: Options, seed: UInt64) {
        self.urls = urls
        self.options = options
        generator = SplitMix64(state: seed)
        round = []
        round = firstRound(from: urls.contains(current) ? current : urls.first)
        drawNextRound()
    }

    /// The image the slideshow wants on screen.
    public var current: URL? { round.indices.contains(position) ? round[position] : nil }

    /// `current` is on screen: its interval starts now (only while playing).
    public mutating func shown(_ url: URL, at now: ContinuousClock.Instant) {
        guard url == current else { return }
        failedRun = []
        shownCurrent = true
        if isPlaying { due = now + options.interval }
    }

    /// The next image once `due` has passed, else nil. Nil and finished at the end without Repeat.
    public mutating func tick(at now: ContinuousClock.Instant) -> URL? {
        guard isPlaying, let due, now >= due else { return nil }
        forward = true
        return advance()
    }

    /// The next or previous image in play order; nil and unchanged at either end of the order.
    public mutating func step(forward: Bool) -> URL? {
        if forward {
            guard position + 1 < round.count || (options.repeats && !nextRound.isEmpty) else { return nil }
        } else {
            guard position > 0 else { return nil }
        }
        self.forward = forward
        if isFinished { isFinished = false; isPaused = true }
        if forward { return advance() }
        position -= 1
        due = nil
        shownCurrent = false
        return current
    }

    /// Playing → paused; paused → playing with a full interval (once `current` has shown); finished → a new round, returned.
    public mutating func togglePause(at now: ContinuousClock.Instant) -> URL? {
        if isFinished {
            guard !urls.isEmpty else { return nil }
            isFinished = false
            isPaused = false
            forward = true
            startNextRound()
            return current
        }
        isPaused.toggle()
        due = isPaused || !shownCurrent ? nil : now + options.interval
        return nil
    }

    /// A panel was open when the image was due: it stays a full interval more.
    public mutating func hold(at now: ContinuousClock.Instant) {
        if due != nil { due = now + options.interval }
    }

    /// `url` couldn't be shown: the next one in the direction of travel that hasn't failed since the
    /// last image shown, turning back at an end of the order (finished there when it was the end).
    /// Nil and finished on `url` when every image of the order failed in a row.
    public mutating func failed(_ url: URL) -> URL? {
        guard url == current else { return nil }
        failedRun.insert(url)
        guard !failedRun.isSuperset(of: urls) else { return finish() }
        let start = self
        var direction = forward
        var turned = false
        while true {
            if let next = step(forward: direction) {
                if failedRun.contains(next) { continue }
                // `step` turns finished into paused; a failure keeps the state it came in with.
                (isFinished, isPaused) = (start.isFinished, start.isPaused)
                if turned, !direction { _ = finish() }
                return next
            }
            if turned { self = start; return finish() }
            direction.toggle()
            turned = true
        }
    }

    /// Drops `url` (Trash, move). If it was current: the next image in play order, else the previous
    /// one, else (the round ran out) finished on its Finder neighbour; nil and finished when none is left.
    public mutating func remove(_ url: URL) -> URL? {
        let finderIndex = urls.firstIndex(of: url) ?? 0
        urls.removeAll { $0 == url }
        let wasCurrent = url == current
        if let index = round.firstIndex(of: url) {
            round.remove(at: index)
            if index < position { position -= 1 }
        }
        drawNextRound()
        guard wasCurrent else { return nil }
        due = nil
        shownCurrent = false
        if current != nil { return current }
        if options.repeats, !nextRound.isEmpty { startNextRound(); return current }
        if position > 0 { position -= 1; return current }
        guard !urls.isEmpty else { return finish() }
        round = [urls[min(finderIndex, urls.count - 1)]]
        position = 0
        drawNextRound()
        _ = finish()
        return current
    }

    /// Interval changes apply to the image on screen, counted from when its interval started (shown,
    /// resumed or held); Shuffle restarts the round from it.
    public mutating func setOptions(_ options: Options) {
        if let due { self.due = due - self.options.interval + options.interval }
        let reshuffle = options.shuffle != self.options.shuffle
        self.options = options
        if reshuffle {
            round = firstRound(from: current)
            position = 0
            drawNextRound()
        }
    }

    /// The next `ahead` images in play order (into the next round with Repeat), then the previous one.
    public func neighbors(ahead: Int) -> [URL] {
        let later = round.dropFirst(position + 1) + (options.repeats ? nextRound : [])
        var result: [URL] = []
        for url in later.prefix(ahead) + (position > 0 ? [round[position - 1]] : [])
        where url != current && !result.contains(url) {
            result.append(url)
        }
        return result
    }

    // MARK: - Order

    private mutating func advance() -> URL? {
        due = nil
        shownCurrent = false
        if position + 1 < round.count {
            position += 1
        } else if options.repeats, !nextRound.isEmpty {
            startNextRound()
        } else {
            return finish()
        }
        return current
    }

    private mutating func finish() -> URL? {
        isFinished = true
        due = nil
        return nil
    }

    private mutating func startNextRound() {
        round = nextRound
        position = 0
        due = nil
        shownCurrent = false
        drawNextRound()
    }

    /// `start` first, then the rest: Finder order to the end of the list, or every other image shuffled.
    private mutating func firstRound(from start: URL?) -> [URL] {
        guard let start, let index = urls.firstIndex(of: start) else { return [] }
        guard options.shuffle else { return Array(urls[index...]) }
        return [start] + urls.filter { $0 != start }.shuffled(using: &generator)
    }

    /// The whole list again; shuffled, it never starts with the image this round ends on.
    private mutating func drawNextRound() {
        guard options.shuffle else { nextRound = urls; return }
        nextRound = urls.shuffled(using: &generator)
        if nextRound.count > 1, nextRound[0] == round.last {
            nextRound.swapAt(0, Int.random(in: 1..<nextRound.count, using: &generator))
        }
    }
}

/// A small seeded generator, so a slideshow's order is reproducible and the struct stays `Equatable`.
private struct SplitMix64: RandomNumberGenerator, Equatable, Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
