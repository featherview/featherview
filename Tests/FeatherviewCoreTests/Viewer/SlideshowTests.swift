import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SlideshowTests {
    let t0 = ContinuousClock.now

    private func urls(_ n: Int) -> [URL] { (1...n).map { URL(fileURLWithPath: "/f/\($0).jpg") } }
    private func u(_ i: Int) -> URL { URL(fileURLWithPath: "/f/\(i).jpg") }
    private func options(seconds: Int = 5, shuffle: Bool = false, repeats: Bool = false) -> Slideshow.Options {
        Slideshow.Options(interval: .seconds(seconds), shuffle: shuffle, repeats: repeats)
    }

    /// Shows the current image at `at` and ticks once its interval is over.
    private func advance(_ show: inout Slideshow, at: ContinuousClock.Instant) -> URL? {
        if let current = show.current { show.shown(current, at: at) }
        return show.tick(at: at + show.options.interval)
    }

    /// Plays `count` images from the current one on, returning what showed (current first).
    private func play(_ show: inout Slideshow, count: Int) -> [URL] {
        var seen = [show.current!]
        var now = t0
        while seen.count < count, let next = advance(&show, at: now) {
            seen.append(next)
            now = now + show.options.interval
        }
        return seen
    }

    @Test func orderedPlaysFromCurrentToEnd() {
        var show = Slideshow(urls: urls(5), from: u(3), options: options(), seed: 1)
        #expect(show.current == u(3))
        #expect(advance(&show, at: t0) == u(4))
        #expect(advance(&show, at: t0) == u(5))
        #expect(advance(&show, at: t0) == nil)
        #expect(show.isFinished)
        #expect(!show.isPlaying)
        #expect(show.current == u(5))
    }

    @Test func unknownCurrentStartsAtFirst() {
        let show = Slideshow(urls: urls(3), from: URL(fileURLWithPath: "/x/9.jpg"), options: options(), seed: 1)
        #expect(show.current == u(1))
    }

    @Test func tickWaitsForShown() {
        var show = Slideshow(urls: urls(5), from: u(3), options: options(), seed: 1)
        #expect(show.due == nil)
        #expect(show.tick(at: t0 + .seconds(60)) == nil)
        show.shown(u(3), at: t0)
        #expect(show.due == t0 + .seconds(5))
        #expect(show.tick(at: t0 + .seconds(4)) == nil)
        #expect(show.tick(at: t0 + .seconds(5)) == u(4))
        #expect(show.due == nil)
        #expect(show.tick(at: t0 + .seconds(60)) == nil)
        show.shown(u(4), at: t0 + .seconds(61))
        #expect(show.tick(at: t0 + .seconds(66)) == u(5))
    }

    @Test func shownForAnotherURLIsIgnored() {
        var show = Slideshow(urls: urls(5), from: u(3), options: options(), seed: 1)
        show.shown(u(2), at: t0)
        #expect(show.due == nil)
    }

    @Test func shuffleRoundHasEachOnce() {
        var show = Slideshow(urls: urls(20), from: u(7), options: options(shuffle: true), seed: 1)
        let round = play(&show, count: 20)
        #expect(round.first == u(7))
        #expect(round.count == 20)
        #expect(Set(round) == Set(urls(20)))
        var other = Slideshow(urls: urls(20), from: u(7), options: options(shuffle: true), seed: 2)
        #expect(play(&other, count: 20) != round)
    }

    @Test(arguments: [2, 3])
    func nextRoundNeverRepeatsLast(_ n: Int) {
        for seed in UInt64(1)...20 {
            var show = Slideshow(urls: urls(n), from: u(1), options: options(shuffle: true, repeats: true), seed: seed)
            let all = play(&show, count: n * 50)
            #expect(all.count == n * 50)
            for start in stride(from: 0, to: all.count, by: n) {
                #expect(Set(all[start..<start + n]) == Set(urls(n)))
                if start > 0 { #expect(all[start] != all[start - 1]) }
            }
        }
    }

    @Test func singleImageRepeats() {
        var show = Slideshow(urls: urls(1), from: u(1), options: options(repeats: true), seed: 1)
        #expect(advance(&show, at: t0) == u(1))
        #expect(advance(&show, at: t0 + .seconds(5)) == u(1))
        #expect(show.isPlaying)
        var once = Slideshow(urls: urls(1), from: u(1), options: options(), seed: 1)
        #expect(advance(&once, at: t0) == nil)
        #expect(once.isFinished)
    }

    @Test func repeatOrderedWrapsToFirst() {
        var show = Slideshow(urls: urls(3), from: u(2), options: options(repeats: true), seed: 1)
        #expect(play(&show, count: 6) == [u(2), u(3), u(1), u(2), u(3), u(1)])
    }

    @Test func stepKeepsPauseAndStopsAtEnds() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        show.shown(u(1), at: t0)
        #expect(show.togglePause(at: t0) == nil)
        #expect(show.isPaused)
        #expect(show.step(forward: false) == nil)  // the round's first
        #expect(show.current == u(1))
        #expect(show.step(forward: true) == u(2))
        #expect(show.isPaused)
        #expect(show.due == nil)
        show.shown(u(2), at: t0)
        #expect(show.due == nil)  // paused: no interval
        #expect(show.step(forward: true) == u(3))
        #expect(show.step(forward: true) == nil)  // the round's last, no repeat
        #expect(show.current == u(3))
    }

    @Test func stepFromFinishedBackIsPaused() {
        var show = Slideshow(urls: urls(2), from: u(1), options: options(), seed: 1)
        _ = play(&show, count: 3)
        #expect(show.isFinished)
        #expect(show.step(forward: true) == nil)
        #expect(show.isFinished)
        #expect(show.step(forward: false) == u(1))
        #expect(!show.isFinished)
        #expect(show.isPaused)
    }

    @Test func stepForwardWithRepeatStartsNextRound() {
        var show = Slideshow(urls: urls(2), from: u(2), options: options(repeats: true), seed: 1)
        #expect(show.step(forward: true) == u(1))
        #expect(show.step(forward: false) == nil)  // a round's first
    }

    @Test func togglePauseRestartsFullInterval() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        show.shown(u(1), at: t0)
        #expect(show.togglePause(at: t0 + .seconds(4)) == nil)
        #expect(show.due == nil)
        #expect(show.tick(at: t0 + .seconds(9)) == nil)
        #expect(show.togglePause(at: t0 + .seconds(10)) == nil)
        #expect(show.isPlaying)
        #expect(show.due == t0 + .seconds(15))
    }

    @Test func resumeBeforeShownWaitsForShown() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(seconds: 1), seed: 1)
        show.shown(u(1), at: t0)
        #expect(show.togglePause(at: t0) == nil)
        #expect(show.step(forward: true) == u(2))
        #expect(show.togglePause(at: t0) == nil)
        #expect(show.isPlaying)
        #expect(show.due == nil)
        #expect(show.tick(at: t0 + .seconds(1)) == nil)
        show.shown(u(2), at: t0 + .milliseconds(1500))
        #expect(show.due == t0 + .milliseconds(2500))
    }

    @Test func finishedPlaysAgain() {
        var show = Slideshow(urls: urls(3), from: u(2), options: options(), seed: 1)
        _ = play(&show, count: 3)
        #expect(show.isFinished)
        #expect(show.togglePause(at: t0) == u(1))
        #expect(show.isPlaying)
        #expect(play(&show, count: 3) == urls(3))  // the whole list
    }

    @Test func holdPushesDue() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        show.shown(u(1), at: t0)
        show.hold(at: t0 + .seconds(5))
        #expect(show.due == t0 + .seconds(10))
    }

    @Test func failedSkipsInDirection() {
        var show = Slideshow(urls: urls(5), from: u(1), options: options(), seed: 1)
        _ = show.step(forward: true)
        _ = show.step(forward: true)
        _ = show.step(forward: true)  // at 4
        #expect(show.step(forward: false) == u(3))
        #expect(show.failed(u(3)) == u(2))
        #expect(show.failed(u(5)) == nil)  // not current
        #expect(show.current == u(2))
        #expect(show.step(forward: true) == u(3))
        #expect(show.failed(u(3)) == u(4))
    }

    @Test func allFailedFinishes() {
        var show = Slideshow(urls: urls(4), from: u(1), options: options(repeats: true), seed: 1)
        #expect(show.failed(u(1)) == u(2))
        #expect(show.failed(u(2)) == u(3))
        #expect(show.failed(u(3)) == u(4))
        #expect(show.failed(u(4)) == nil)
        #expect(show.isFinished)
        #expect(show.current == u(4))
    }

    @Test func failedAtTheStartTurnsBack() {
        var show = Slideshow(urls: urls(5), from: u(1), options: options(), seed: 1)
        _ = show.step(forward: true)  // at 2
        #expect(show.step(forward: false) == u(1))
        #expect(show.failed(u(1)) == u(2))
        #expect(!show.isFinished)
        #expect(show.step(forward: true) == u(3))
    }

    @Test func failedAtTheEndFinishesOnThePrevious() {
        var show = Slideshow(urls: urls(5), from: u(4), options: options(), seed: 1)
        #expect(advance(&show, at: t0) == u(5))
        #expect(show.failed(u(5)) == u(4))
        #expect(show.isFinished)
        #expect(show.current == u(4))
        show.shown(u(4), at: t0)
        #expect(show.due == nil)
    }

    @Test func failedAfterFinishingStaysFinished() {
        var show = Slideshow(urls: urls(5), from: u(1), options: options(), seed: 1)
        #expect(play(&show, count: 5) == urls(5))
        #expect(show.failed(u(5)) == u(4))
        #expect(show.failed(u(4)) == u(3))
        #expect(show.isFinished)
        #expect(!show.isPaused)
        #expect(show.current == u(3))
    }

    @Test func failedWithNowhereLeftFinishesOnTheFailedOne() {
        var show = Slideshow(urls: urls(4), from: u(3), options: options(), seed: 1)
        #expect(advance(&show, at: t0) == u(4))
        #expect(show.failed(u(4)) == u(3))
        #expect(show.failed(u(3)) == nil)
        #expect(show.isFinished)
        #expect(!show.isPaused)
        #expect(show.current == u(3))
    }

    @Test func failedRunCrossingRoundsFindsTheReadableOne() {
        for seed in UInt64(1)...200 {
            var show = Slideshow(urls: urls(4), from: u(1), options: options(shuffle: true, repeats: true), seed: seed)
            var next = advance(&show, at: t0)
            var tries = 0
            while let url = next, url != u(1), tries < 20 {
                next = show.failed(url)
                tries += 1
            }
            #expect(next == u(1), "seed \(seed)")
            #expect(!show.isFinished)
        }
    }

    @Test func shownResetsTheFailureRun() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(repeats: true), seed: 1)
        #expect(show.failed(u(1)) == u(2))
        #expect(show.failed(u(2)) == u(3))
        show.shown(u(3), at: t0)
        #expect(advance(&show, at: t0) == u(1))
        #expect(show.failed(u(1)) == u(2))
        #expect(!show.isFinished)
    }

    @Test func removeCurrentGoesToNext() {
        var show = Slideshow(urls: urls(4), from: u(2), options: options(), seed: 1)
        show.shown(u(2), at: t0)
        #expect(show.remove(u(2)) == u(3))
        #expect(show.current == u(3))
        #expect(show.due == nil)
        var atEnd = Slideshow(urls: urls(4), from: u(3), options: options(), seed: 1)
        _ = atEnd.step(forward: true)
        #expect(atEnd.remove(u(4)) == u(3))  // nothing next: the previous
    }

    @Test func removeUpcomingDropsIt() {
        var show = Slideshow(urls: urls(4), from: u(1), options: options(shuffle: true, repeats: true), seed: 3)
        let removed = show.neighbors(ahead: 1)[0]
        #expect(show.remove(removed) == nil)
        #expect(show.current == u(1))
        #expect(!show.neighbors(ahead: 5).contains(removed))
        let played = play(&show, count: 30)
        #expect(!played.contains(removed))
        #expect(Set(played) == Set(urls(4)).subtracting([removed]))
    }

    @Test func removeShownKeepsPosition() {
        var show = Slideshow(urls: urls(4), from: u(1), options: options(), seed: 1)
        _ = show.step(forward: true)
        _ = show.step(forward: true)  // at 3
        #expect(show.remove(u(1)) == nil)
        #expect(show.current == u(3))
        #expect(show.step(forward: true) == u(4))
    }

    @Test func removeLastOfRoundFinishesOnFinderNeighbour() {
        var show = Slideshow(urls: urls(5), from: u(5), options: options(), seed: 1)
        #expect(show.remove(u(5)) == u(4))
        #expect(show.current == u(4))
        #expect(show.isFinished)
        var first = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        _ = first.step(forward: true)
        #expect(first.remove(u(1)) == nil)  // not current
        #expect(first.remove(u(2)) == u(3))
        #expect(first.remove(u(3)) == nil)  // the last one gone
        #expect(first.isFinished)
    }

    @Test func removeLastLeftFinishes() {
        var show = Slideshow(urls: urls(1), from: u(1), options: options(repeats: true), seed: 1)
        #expect(show.remove(u(1)) == nil)
        #expect(show.isFinished)
        #expect(show.current == nil)
        #expect(show.neighbors(ahead: 2).isEmpty)
        #expect(show.tick(at: t0 + .seconds(60)) == nil)
    }

    @Test func shuffleToggleRestartsFromCurrent() {
        var show = Slideshow(urls: urls(10), from: u(1), options: options(), seed: 1)
        for _ in 0..<2 { _ = show.step(forward: true) }  // at 3
        show.setOptions(options(shuffle: true), shownAt: nil)
        #expect(show.current == u(3))
        let round = play(&show, count: 10)
        #expect(round.count == 10)
        #expect(Set(round) == Set(urls(10)))
    }

    @Test func intervalChangeAppliesNow() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        show.shown(u(1), at: t0)
        show.setOptions(options(seconds: 2), shownAt: t0)
        #expect(show.due == t0 + .seconds(2))
        #expect(show.options.interval == .seconds(2))
    }

    @Test func neighborsCrossIntoNextRound() {
        var show = Slideshow(urls: urls(3), from: u(1), options: options(repeats: true), seed: 1)
        _ = show.step(forward: true)
        _ = show.step(forward: true)  // at 3, the round's last
        // The next round's first two (1, 2), then the previous one (2, already listed).
        #expect(show.neighbors(ahead: 2) == [u(1), u(2)])
        var once = Slideshow(urls: urls(3), from: u(1), options: options(), seed: 1)
        _ = once.step(forward: true)
        _ = once.step(forward: true)
        #expect(once.neighbors(ahead: 2) == [u(2)])
        var middle = Slideshow(urls: urls(5), from: u(2), options: options(), seed: 1)
        _ = middle.step(forward: true)  // at 3
        #expect(middle.neighbors(ahead: 2) == [u(4), u(5), u(2)])
    }

    @Test func intervalsAreTheMenuChoices() {
        #expect(Slideshow.intervals == [1, 2, 3, 5, 10, 20, 30, 60])
    }
}
