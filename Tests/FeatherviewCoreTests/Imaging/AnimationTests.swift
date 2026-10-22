import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct AnimationTests {
    @Test func unclampedDelaysForEveryFormat() throws {
        let dir = try Fixtures.makeTempDir()
        // ImageIO's HEICS writer gives the last frame the one before's delay, so those two match.
        let delays = [0.5, 0.04, 0.04]
        let files = [
            try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: delays),
            try Fixtures.writeAPNG(to: dir.appendingPathComponent("a.png"), delays: delays),
            try Fixtures.writeHEICS(to: dir.appendingPathComponent("a.heics"), delays: delays),
            try Fixtures.writeAnimatedWebP(to: dir.appendingPathComponent("a.webp"), delays: delays),
        ]
        for file in files {
            #expect(Animation.read(file)?.delays == [.milliseconds(500), .milliseconds(40), .milliseconds(40)],
                    "\(file.lastPathComponent)")
        }
    }

    @Test func tinyDelaysCountAsHundredMilliseconds() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("t.gif"), delays: [0, 0.01, 0.02])
        #expect(Animation.read(url)?.delays == [.milliseconds(100), .milliseconds(100), .milliseconds(20)])
        #expect(Animation.delay(seconds: nil) == .milliseconds(100))
    }

    @Test func stillsAreNotAnimations() throws {
        let dir = try Fixtures.makeTempDir()
        let stills = [
            try Fixtures.writeImage(to: dir.appendingPathComponent("s.jpg"), width: 8, height: 6),
            try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("one.gif"), delays: [0.1]),
            try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("p.tif"), pages: 3),
            try Fixtures.writeImage(to: dir.appendingPathComponent("s.png"), width: 8, height: 6, type: .png),
        ]
        for still in stills {
            #expect(Animation.read(still) == nil, "\(still.lastPathComponent)")
        }
    }

    @Test func apngExtensionReadsAsPNG() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeAPNG(to: dir.appendingPathComponent("a.apng"), delays: [0.04, 0.04])
        #expect(ImageFormats.isDecodable(url))
        #expect(Animation.read(url)?.frameCount == 2)
        #expect(try ImageDecoder.decode(url).width == 8)
    }

    @Test func mayAnimateByExtension() {
        // .ani joins once ANIDecoder gives its delays (Task 2).
        for ext in ["gif", "apng", "heics", "webp"] {
            #expect(ImageFormats.mayAnimate(URL(filePath: "/x/a.\(ext)")), "\(ext)")
        }
        for ext in ["jpg", "tif", "qoi"] {
            #expect(!ImageFormats.mayAnimate(URL(filePath: "/x/a.\(ext)")), "\(ext)")
        }
    }

    @Test func truncatedGIFDoesNotCrash() throws {
        let dir = try Fixtures.makeTempDir()
        let full = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("f.gif"), delays: [0.04, 0.04, 0.04, 0.04],
                                                 width: 64, height: 48)
        let data = try Data(contentsOf: full)
        let url = dir.appendingPathComponent("cut.gif")
        try data.prefix(data.count * 7 / 10).write(to: url)
        if let animation = Animation.read(url) {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(animation.frameCount == CGImageSourceGetCount(source))
        }
    }
}
