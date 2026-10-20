import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ANIDecoderTests {
    static func le32(_ v: Int) -> [UInt8] { [0, 8, 16, 24].map { UInt8(v >> $0 & 0xFF) } }
    static func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
        Array(id.utf8) + le32(body.count) + body + (body.count % 2 == 1 ? [0] : [])
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

    /// RIFF "ACON": the "anih" header, an optional "seq " order, the frames in LIST "fram".
    static func ani(frames: [[UInt8]], sequence: [Int]? = nil, iconFlag: Bool = true) -> [UInt8] {
        let anih = [36, frames.count, sequence?.count ?? frames.count, 0, 0, 0, 0, 10, iconFlag ? 1 : 0].flatMap(le32)
        var body = Array("ACON".utf8) + chunk("anih", anih)
        if let sequence { body += chunk("seq ", sequence.flatMap(le32)) }
        body += chunk("LIST", Array("fram".utf8) + frames.flatMap { chunk("icon", $0) })
        return Array("RIFF".utf8) + le32(body.count) + body
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
}
