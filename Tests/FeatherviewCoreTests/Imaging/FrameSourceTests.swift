import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct FrameSourceTests {
    static let screen = [PixelSize(width: 800, height: 600)]

    /// A looping GIF of the given frames, for frames that aren't solid (`Fixtures.writeAnimatedGIF` only writes solid ones).
    static func writeGIF(to url: URL, frames: [CGImage]) throws -> URL {
        try Fixtures.writeSequence(to: url, type: UTType.gif.identifier, dictionary: kCGImagePropertyGIFDictionary,
                                   delayKey: kCGImagePropertyGIFDelayTime, delays: Array(repeating: 0.04, count: frames.count),
                                   frame: { frames[$0] },
                                   fileProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]])
    }

    static func solid(_ n: Int, width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: CGFloat(40 * n) / 255, green: n == 1 ? 1 : 0, blue: n == 2 ? 1 : 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func frameZeroMatchesStillDecode() async throws {
        let url = try Fixtures.writeAnimatedGIF(to: Fixtures.makeTempDir().appendingPathComponent("a.gif"),
                                                delays: [0.04, 0.04, 0.04], width: 400, height: 300)
        let still = try ImageDecoder.decode(url, halvingSteps: true, fitting: Self.screen)
        let frame = try await FrameSource(url: url, target: .fit(Self.screen), colorSpace: nil).frame(0)
        #expect(frame.width == still.width)
        #expect(frame.height == still.height)
        #expect(frame.bitsPerComponent == still.bitsPerComponent)
    }

    @Test func framesAreComposited() async throws {
        // ImageIO's GIF writer scales a smaller frame to the canvas, so frame 2 is full size and clear
        // outside its 10×10 corner: only compositing shows frame 1 there.
        let corner = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        corner.draw(Self.solid(2, width: 10, height: 10), in: CGRect(x: 0, y: 20, width: 10, height: 10))
        let frames = [Self.solid(0, width: 40, height: 30), Self.solid(1, width: 40, height: 30), corner.makeImage()!]
        let url = try Self.writeGIF(to: Fixtures.makeTempDir().appendingPathComponent("delta.gif"), frames: frames)
        // ImageIO writes disposal 2 (restore to background) and has no key for it: patch every graphic control
        // extension to disposal 1 (keep), as delta-frame GIFs are.
        var bytes = [UInt8](try Data(contentsOf: url))
        for i in 0..<(bytes.count - 3) where bytes[i..<i + 3] == [0x21, 0xF9, 0x04] {
            bytes[i + 3] = bytes[i + 3] & ~0x1C | 0x04
        }
        try Data(bytes).write(to: url)
        let source = try FrameSource(url: url, target: .full, colorSpace: nil)
        let one = try await source.frame(1)
        let two = try await source.frame(2)
        #expect(two.width == 40 && two.height == 30)
        let (oneRGBA, twoRGBA) = (try #require(RGBAImage(one)), try #require(RGBAImage(two)))
        #expect(twoRGBA[30, 25] == oneRGBA[30, 25])
        #expect(twoRGBA[30, 25] != twoRGBA[2, 2])
    }

    @Test func stepTargetHalves() async throws {
        let url = try Fixtures.writeAnimatedGIF(to: Fixtures.makeTempDir().appendingPathComponent("a.gif"),
                                                delays: [0.04, 0.04], width: 400, height: 300)
        let frame = try await FrameSource(url: url, target: .step(1), colorSpace: nil).frame(1)
        #expect(frame.width == 200)
        #expect(frame.height == 150)
    }

    @Test func truncatedAnimationStopsAtLastGoodFrame() async throws {
        let dir = try Fixtures.makeTempDir()
        let two = try Data(contentsOf: Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("two.gif"),
                                                                 delays: [0.04, 0.04], width: 40, height: 30))
        let four = try Data(contentsOf: Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("four.gif"),
                                                                  delays: [0.04, 0.04, 0.04, 0.04], width: 40, height: 30))
        // The two-frame file without its trailer is the four-frame file's start; cut a few bytes into frame 2.
        let url = dir.appendingPathComponent("cut.gif")
        try four.prefix(two.count - 1 + 20).write(to: url)
        let source = try FrameSource(url: url, target: .full, colorSpace: nil)
        _ = try await source.frame(0)
        _ = try await source.frame(1)
        await #expect(throws: DecodeError.unreadable(url)) { try await source.frame(2) }
    }

    /// A toy own format: byte 0 frame count; frame n is a 4×2 solid grey of 40·n.
    static let toy = OwnFormat(
        name: "TOYANIM", extensions: ["fvanim"],
        size: { _, _ in CGSize(width: 4, height: 2) },
        pageCount: { data in Int(data.first ?? 1) },
        decode: { data, index, _ in
            guard index < Int(data.first ?? 0) else { throw OwnDecodeError.corrupt }
            var image = RGBAImage(width: 4, height: 2)
            for y in 0..<2 { for x in 0..<4 { image[x, y] = (UInt8(40 * index), 0, 0, 255) } }
            return image.makeCGImage()!
        },
        delays: { data in Array(repeating: 0.04, count: Int(data.first ?? 1)) })

    @Test func ownFormatFrames() async throws {
        OwnDecoders.register(Self.toy)
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.fvanim")
        try Data([3]).write(to: url)
        #expect(Animation.read(url)?.frameCount == 3)
        let source = try FrameSource(url: url, target: .fit(Self.screen), colorSpace: nil)
        let frame = try await source.frame(1)
        #expect(try #require(RGBAImage(frame))[1, 1].r == 40)
        await #expect(throws: DecodeError.unreadable(url)) { try await source.frame(3) }
    }
}
