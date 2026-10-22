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

}
