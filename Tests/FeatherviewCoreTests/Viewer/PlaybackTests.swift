import Testing
@testable import FeatherviewCore

@Suite struct PlaybackTests {
    @Test func advanceWrapsToFirstFrame() {
        var playback = Playback(frameCount: 3, playing: true)
        playback.advance()
        playback.advance()
        #expect(playback.frame == 2)
        playback.advance()
        #expect(playback.frame == 0)
    }

    @Test func stepPausesAndStopsAtEnds() {
        var playback = Playback(frameCount: 3, playing: true)
        var moved = playback.step(forward: false)
        #expect(!moved)
        #expect(playback.frame == 0)
        #expect(!playback.isPlaying)
        playback.step(forward: true)
        moved = playback.step(forward: true)
        #expect(moved)
        #expect(playback.frame == 2)
        moved = playback.step(forward: true)
        #expect(!moved)
        #expect(playback.frame == 2)
        moved = playback.step(forward: false)
        #expect(moved)
        #expect(playback.frame == 1)
    }

    @Test func playAfterStepAtEndWraps() {
        var playback = Playback(frameCount: 2, playing: true)
        playback.step(forward: true)
        playback.togglePlaying()
        #expect(playback.isPlaying)
        playback.advance()
        #expect(playback.frame == 0)
    }

    @Test func togglePlayingKeepsFrame() {
        var playback = Playback(frameCount: 4, playing: false)
        playback.step(forward: true)
        playback.togglePlaying()
        #expect(playback.frame == 1)
        #expect(playback.isPlaying)
        playback.togglePlaying()
        #expect(playback.frame == 1)
        #expect(!playback.isPlaying)
    }

    @Test func keepsAllUnderBudget() {
        #expect(FrameStore.keepsAll(frameBytes: 1 << 20, count: 64))
        #expect(!FrameStore.keepsAll(frameBytes: 30 << 20, count: 3))
    }

    @Test func wantedWindowWraps() {
        #expect(FrameStore.wanted(shown: 5, count: 6, keepsAll: false) == [5, 0, 1])
        #expect(FrameStore.wanted(shown: 1, count: 2, keepsAll: false) == [1, 0])
    }

    @Test func wantedAllStartsAtShown() {
        #expect(FrameStore.wanted(shown: 2, count: 4, keepsAll: true) == [2, 3, 0, 1])
    }
}
