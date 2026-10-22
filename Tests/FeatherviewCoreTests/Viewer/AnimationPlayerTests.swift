import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@MainActor @Suite struct AnimationPlayerTests {
    /// A frame 0 big enough that the frames don't all fit `FrameStore.budget`, so only three are kept.
    static func bigFirst() -> CGImage {
        let context = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    static func gif(frames: Int, delay: Double) throws -> URL {
        try Fixtures.writeAnimatedGIF(to: Fixtures.makeTempDir().appendingPathComponent("a.gif"),
                                      delays: Array(repeating: delay, count: frames))
    }

    @Test func heldStepKeepsOnlyWantedDecodes() async throws {
        let url = try Self.gif(frames: 30, delay: 0.04)
        let player = AnimationPlayer(colorSpace: nil)
        player.start(url: url, animation: try #require(Animation.read(url)), target: .full, first: Self.bigFirst(),
                     playing: false)
        // A key repeat faster than a decode: each step's decode starts before the one before has shown.
        for _ in 0..<20 {
            player.step(forward: true)
            await Task.yield()
            #expect(player.decodes.count <= 3)
        }
        player.stop()
    }

    @Test func playerReleasedWhilePlayingGoesAway() async throws {
        let url = try Self.gif(frames: 5, delay: 0.02)
        var player: AnimationPlayer? = AnimationPlayer(colorSpace: nil)
        weak let weakPlayer = player
        player?.start(url: url, animation: try #require(Animation.read(url)), target: .full,
                      first: Self.bigFirst(), playing: true)
        try await Task.sleep(for: .milliseconds(100))
        player = nil
        for _ in 0..<50 where weakPlayer != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(weakPlayer == nil)
    }

    @Test func stepAtEndKeepsTheFrameOnItsWay() async throws {
        let url = try Self.gif(frames: 2, delay: 0.04)
        let player = AnimationPlayer(colorSpace: nil)
        var shown: [CGImage] = []
        player.onFrame = { shown.append($0) }
        player.start(url: url, animation: try #require(Animation.read(url)), target: .full, first: Self.bigFirst(),
                     playing: false)
        #expect(player.step(forward: true))
        // A held key: the next step comes before frame 1 has decoded, and can't move.
        #expect(!player.step(forward: true))
        for _ in 0..<50 where shown.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(shown.count == 1)
        #expect(player.pausedFrame == 1)
        player.stop()
    }

    @Test func stopShowingPutsFrameZeroBack() async throws {
        let url = try Self.gif(frames: 3, delay: 0.04)
        let player = AnimationPlayer(colorSpace: nil)
        var shown: [CGImage] = []
        player.onFrame = { shown.append($0) }
        let first = Self.bigFirst()
        player.start(url: url, animation: try #require(Animation.read(url)), target: .full, first: first, playing: false)
        player.stop(showing: first)
        // Frame 0 is on the canvas already.
        #expect(shown.isEmpty)
        player.start(url: url, animation: try #require(Animation.read(url)), target: .full, first: first, playing: false)
        player.step(forward: true)
        for _ in 0..<50 where player.current == nil { try await Task.sleep(for: .milliseconds(20)) }
        player.stop(showing: first)
        #expect(shown.last === first)
    }
}
