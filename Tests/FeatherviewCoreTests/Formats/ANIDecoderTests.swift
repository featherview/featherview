import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ANIDecoderTests {
    static func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
        Array(id.utf8) + Fixtures.le32(body.count) + body + (body.count % 2 == 1 ? [0] : [])
    }

    /// An ICO holding one image per size, each filled with `colour`.
    static func ico(sizes: [Int], colour: (UInt8, UInt8, UInt8, UInt8)) throws -> [UInt8] {
        let url = try Fixtures.makeTempDir().appendingPathComponent("f.ico")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.ico.identifier as CFString, sizes.count, nil))
        for side in sizes {
            var image = RGBAImage(width: side, height: side)
            for y in 0..<side { for x in 0..<side { image[x, y] = colour } }
            CGImageDestinationAddImage(dest, try #require(image.makeCGImage()), nil)
        }
        #expect(CGImageDestinationFinalize(dest))
        return Array(try Data(contentsOf: url))
    }

    /// The ICO as a CUR (type 2, hotspot 0, 0), as Windows' cursors are.
    static func cur(sizes: [Int], colour: (UInt8, UInt8, UInt8, UInt8)) throws -> [UInt8] {
        var bytes = try ico(sizes: sizes, colour: colour)
        bytes[2] = 2
        for entry in 0..<sizes.count {
            let hotspot = 6 + 16 * entry + 4
            bytes.replaceSubrange(hotspot..<hotspot + 4, with: [0, 0, 0, 0])
        }
        return bytes
    }

    /// RIFF "ACON": the "anih" header (rate in jiffies), optional "seq " order and "rate" per step, the
    /// frames in LIST "fram".
    static func ani(frames: [[UInt8]], sequence: [Int]? = nil, rate: Int = 10, rates: [Int]? = nil,
                    iconFlag: Bool = true) -> [UInt8] {
        let anih = [36, frames.count, sequence?.count ?? frames.count, 0, 0, 0, 0, rate, iconFlag ? 1 : 0].flatMap(Fixtures.le32)
        var body = Array("ACON".utf8) + chunk("anih", anih)
        if let sequence { body += chunk("seq ", sequence.flatMap(Fixtures.le32)) }
        if let rates { body += chunk("rate", rates.flatMap(Fixtures.le32)) }
        body += chunk("LIST", Array("fram".utf8) + frames.flatMap { chunk("icon", $0) })
        return Array("RIFF".utf8) + Fixtures.le32(body.count) + body
    }

    @Test func showsTheLargestImageOfTheFirstFrame() throws {
        let frames = [try Self.ico(sizes: [16, 32], colour: (255, 0, 0, 255)), try Self.ico(sizes: [16], colour: (0, 0, 255, 255))]
        let data = Data(Self.ani(frames: frames))
        #expect(ANIDecoder.format.size(data, 0) == CGSize(width: 32, height: 32))
        let image = try #require(RGBAImage(try ANIDecoder.format.decode(data, 0, nil)))
        #expect(image.width == 32 && image[5, 5] == (255, 0, 0, 255))
    }

    @Test func theSequenceDecidesTheFirstFrame() throws {
        let frames = [try Self.ico(sizes: [16], colour: (255, 0, 0, 255)), try Self.ico(sizes: [16], colour: (0, 0, 255, 255))]
        let image = try #require(RGBAImage(try ANIDecoder.format.decode(Data(Self.ani(frames: frames, sequence: [1, 0])), 0, nil)))
        #expect(image[5, 5] == (0, 0, 255, 255))
    }

    @Test func decodesThroughImageDecoder() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.ani")
        try Data(Self.ani(frames: [try Self.ico(sizes: [32], colour: (0, 255, 0, 255))])).write(to: url)
        #expect(ImageFormats.isDecodable(url) && ImageDecoder.displaySize(of: url) == CGSize(width: 32, height: 32))
        #expect(try ImageDecoder.decode(url).width == 32)
    }

    @Test func rejectsBadFiles() throws {
        let good = Self.ani(frames: [try Self.ico(sizes: [16], colour: (0, 0, 0, 255))])
        #expect(throws: OwnDecodeError.notThisFormat) { try ANIDecoder.format.decode(Data("RIFF\0\0\0\0WAVE".utf8), 0, nil) }
        #expect(throws: OwnDecodeError.self) { try ANIDecoder.format.decode(Data(good.prefix(60)), 0, nil) }
        #expect(throws: OwnDecodeError.unsupported) {
            try ANIDecoder.format.decode(Data(Self.ani(frames: [[1, 2, 3]], iconFlag: false)), 0, nil)
        }
        #expect(throws: OwnDecodeError.corrupt) {
            try ANIDecoder.format.decode(Data(Self.ani(frames: [try Self.ico(sizes: [16], colour: (0, 0, 0, 255))], sequence: [7])), 0, nil)
        }
    }

    static let colours: [(UInt8, UInt8, UInt8, UInt8)] = [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255)]
    static func threeFrames() throws -> [[UInt8]] { try colours.map { try ico(sizes: [16], colour: $0) } }

    @Test func stepsFollowSequence() throws {
        let data = Data(Self.ani(frames: try Self.threeFrames(), sequence: [2, 0, 2]))
        for (step, frame) in [(0, 2), (1, 0), (2, 2)] {
            let image = try #require(RGBAImage(try ANIDecoder.format.decode(data, step, nil)))
            #expect(image[5, 5] == Self.colours[frame], "step \(step)")
        }
        #expect(ANIDecoder.format.delays?(data)?.count == 3)
        #expect(ANIDecoder.format.pageCount(data) == 1)
    }

    @Test func ratesPerStep() throws {
        let data = Data(Self.ani(frames: try Self.threeFrames(), rates: [6, 30, 6]))
        #expect(ANIDecoder.format.delays?(data) == [0.1, 0.5, 0.1])
    }

    @Test func headerRateWithoutRateChunk() throws {
        let data = Data(Self.ani(frames: try Self.threeFrames(), rate: 10))
        let sixth: Double = 1.0 / 6
        #expect(ANIDecoder.format.delays?(data) == [sixth, sixth, sixth])
    }

    @Test func zeroRateIsHundredMilliseconds() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("z.ani")
        try Data(Self.ani(frames: try Self.threeFrames(), rate: 0)).write(to: url)
        #expect(Animation.read(url)?.delays == Array(repeating: .milliseconds(100), count: 3))
    }

    @Test func outOfRangeStepIsCorrupt() throws {
        let data = Data(Self.ani(frames: try Self.threeFrames(), sequence: [0, 9, 1]))
        #expect(throws: OwnDecodeError.corrupt) { try ANIDecoder.format.decode(data, 1, nil) }
        #expect(throws: OwnDecodeError.corrupt) { try ANIDecoder.format.decode(data, 3, nil) }
        #expect(ANIDecoder.format.size(data, 1) == nil)
        let image = try #require(RGBAImage(try ANIDecoder.format.decode(data, 0, nil)))
        #expect(image[5, 5] == Self.colours[0])
    }

    @Test func busyCursorShape() throws {
        let frames = try (0..<18).map { n in try Self.cur(sizes: [64, 48, 32], colour: (UInt8(n * 10), 0, 0, 255)) }
        let data = Data(Self.ani(frames: frames, rate: 3))
        #expect(ANIDecoder.format.delays?(data) == Array(repeating: 0.05, count: 18))
        for step in 0..<18 {
            #expect(ANIDecoder.format.size(data, step) == CGSize(width: 64, height: 64))
            let image = try #require(RGBAImage(try ANIDecoder.format.decode(data, step, nil)))
            let colour: (UInt8, UInt8, UInt8, UInt8) = (UInt8(step * 10), 0, 0, 255)
            #expect(image.width == 64)
            #expect(image[5, 5] == colour, "step \(step)")
        }
    }
}
