import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ILBMDecoderTests {

    static func chunk(_ id: String, _ bytes: [UInt8]) -> [UInt8] {
        Array(id.utf8) + Fixtures.be32(bytes.count) + bytes + (bytes.count % 2 == 1 ? [0] : [])
    }

    static func form(_ chunks: [[UInt8]], kind: String = "ILBM") -> Data {
        let content = Array(kind.utf8) + chunks.joined()
        return Data(Array("FORM".utf8) + Fixtures.be32(content.count) + content)
    }

    static func bmhd(width: Int, height: Int, planes: Int, masking: Int = 0, compression: Int = 0,
                     transparent: Int = 0) -> [UInt8] {
        chunk("BMHD", Fixtures.be16(width) + Fixtures.be16(height) + [0, 0, 0, 0, UInt8(planes), UInt8(masking), UInt8(compression), 0]
              + Fixtures.be16(transparent) + [10, 11] + Fixtures.be16(width) + Fixtures.be16(height))
    }

    static func cmap(_ colors: [(UInt8, UInt8, UInt8)]) -> [UInt8] { chunk("CMAP", colors.flatMap { [$0.0, $0.1, $0.2] }) }

    /// Rows of colour indices as interleaved bitplanes, then an optional mask plane per row.
    static func planar(_ rows: [[Int]], planes: Int, mask: [[Int]]? = nil) -> [UInt8] {
        let rowBytes = (rows[0].count + 15) / 16 * 2
        func plane(_ bits: [Int]) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: rowBytes)
            for (x, bit) in bits.enumerated() where bit != 0 { out[x / 8] |= 0x80 >> (x % 8) }
            return out
        }
        return rows.indices.flatMap { y in
            (0..<planes).flatMap { p in plane(rows[y].map { $0 >> p & 1 }) } + (mask.map { plane($0[y]) } ?? [])
        }
    }

    static let fourColors: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255)]

    @Test func twoPlanePalette() throws {
        let data = Self.form([Self.bmhd(width: 3, height: 1, planes: 2), Self.cmap(Self.fourColors),
                              Self.chunk("BODY", Self.planar([[3, 1, 2]], planes: 2))])
        let image = try ILBMDecoder.decode(data)
        #expect(image[0, 0] == (0, 0, 255, 255) && image[1, 0] == (255, 0, 0, 255) && image[2, 0] == (0, 255, 0, 255))
        #expect(try ILBMDecoder.size(data) == (3, 1))
    }

    @Test func byteRun1() throws {
        // Row 0: 0xFF = repeat 0xF0 twice. 0x80 = no-op. Row 1: 0x01 = two literal bytes.
        let body: [UInt8] = [0xFF, 0xF0, 0x80, 0x01, 0x0F, 0xFF]
        let data = Self.form([Self.bmhd(width: 16, height: 2, planes: 1, compression: 1), Self.cmap(Self.fourColors),
                              Self.chunk("BODY", body)])
        let image = try ILBMDecoder.decode(data)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[4, 0] == (0, 0, 0, 255) && image[8, 0] == (255, 0, 0, 255))
        #expect(image[0, 1] == (0, 0, 0, 255) && image[4, 1] == (255, 0, 0, 255) && image[15, 1] == (255, 0, 0, 255))
    }

    @Test func byteRun1NeverWritesPastTheImage() throws {
        // A 128-byte literal run for an image of 2 bytes.
        let data = Self.form([Self.bmhd(width: 16, height: 1, planes: 1, compression: 1),
                              Self.chunk("BODY", [0x7F] + [UInt8](repeating: 0xFF, count: 128))])
        #expect(try ILBMDecoder.decode(data)[15, 0] == (255, 255, 255, 255))  // no CMAP: greyscale ramp
    }

    @Test func extraHalfBrite() throws {
        var colors = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 32)
        colors[1] = (200, 100, 50)
        let data = Self.form([Self.bmhd(width: 2, height: 1, planes: 6), Self.cmap(colors), Self.chunk("CAMG", Fixtures.be32(0x80)),
                              Self.chunk("BODY", Self.planar([[1, 33]], planes: 6))])
        let image = try ILBMDecoder.decode(data)
        #expect(image[0, 0] == (200, 100, 50, 255))
        #expect(image[1, 0] == (100, 50, 25, 255))
    }

    @Test func ham6() throws {
        var colors = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 16)
        colors[1] = (0x10, 0x20, 0x30)
        // Palette 1; red := 15×17; green := 0; blue := 5×17.
        let row = [0b00_0001, 0b10_1111, 0b11_0000, 0b01_0101]
        let data = Self.form([Self.bmhd(width: 4, height: 1, planes: 6), Self.cmap(colors), Self.chunk("CAMG", Fixtures.be32(0x800)),
                              Self.chunk("BODY", Self.planar([row], planes: 6))])
        let image = try ILBMDecoder.decode(data)
        #expect(image[0, 0] == (0x10, 0x20, 0x30, 255))
        #expect(image[1, 0] == (255, 0x20, 0x30, 255))
        #expect(image[2, 0] == (255, 0, 0x30, 255))
        #expect(image[3, 0] == (255, 0, 85, 255))
    }

    @Test func ham8KeepsTheLowTwoBits() throws {
        var colors = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 64)
        colors[0] = (0x03, 0x03, 0x03)
        let row = [0b10_000001]  // modify red from the row's start colour 0: 1 << 2 | 3
        let data = Self.form([Self.bmhd(width: 1, height: 1, planes: 8), Self.cmap(colors), Self.chunk("CAMG", Fixtures.be32(0x800)),
                              Self.chunk("BODY", Self.planar([row], planes: 8))])
        #expect(try ILBMDecoder.decode(data)[0, 0] == (0x07, 0x03, 0x03, 255))
    }

    @Test func twentyFourPlanes() throws {
        let data = Self.form([Self.bmhd(width: 1, height: 1, planes: 24),
                              Self.chunk("BODY", Self.planar([[1 | 2 << 8 | 3 << 16]], planes: 24))])
        #expect(try ILBMDecoder.decode(data)[0, 0] == (1, 2, 3, 255))
    }

    @Test func maskPlaneAndTransparentColour() throws {
        let masked = Self.form([Self.bmhd(width: 2, height: 1, planes: 1, masking: 1), Self.cmap(Self.fourColors),
                                Self.chunk("BODY", Self.planar([[1, 1]], planes: 1, mask: [[1, 0]]))])
        let image = try ILBMDecoder.decode(masked)
        #expect(image[0, 0] == (255, 0, 0, 255) && image[1, 0].a == 0)

        let keyed = Self.form([Self.bmhd(width: 2, height: 1, planes: 2, masking: 2, transparent: 2), Self.cmap(Self.fourColors),
                               Self.chunk("BODY", Self.planar([[2, 3]], planes: 2))])
        let other = try ILBMDecoder.decode(keyed)
        #expect(other[0, 0].a == 0 && other[1, 0] == (0, 0, 255, 255))
    }

    @Test func chunkyPBM() throws {
        // 3 pixels, row padded to 4 bytes; an unknown odd-length chunk before BODY is skipped.
        let data = Self.form([Self.bmhd(width: 3, height: 1, planes: 8), Self.cmap(Self.fourColors),
                              Self.chunk("DPPS", [1, 2, 3]), Self.chunk("BODY", [2, 0, 1, 9])], kind: "PBM ")
        let image = try ILBMDecoder.decode(data)
        #expect(image[0, 0] == (0, 255, 0, 255) && image[1, 0] == (0, 0, 0, 255) && image[2, 0] == (255, 0, 0, 255))
    }

    @Test func badFilesThrow() {
        let header = Self.bmhd(width: 16, height: 4, planes: 2)
        var cut = [UInt8](Self.form([header, Self.chunk("BODY", [UInt8](repeating: 0, count: 16))]))
        cut.removeLast(4)
        #expect(throws: OwnDecodeError.truncated) { try ILBMDecoder.decode(Data(cut)) }
        #expect(throws: OwnDecodeError.truncated) {  // BODY too short for the image
            try ILBMDecoder.decode(Self.form([header, Self.chunk("BODY", [0, 0])]))
        }
        #expect(throws: OwnDecodeError.corrupt) { try ILBMDecoder.decode(Self.form([Self.chunk("BODY", [0, 0])])) }
        #expect(throws: OwnDecodeError.corrupt) {
            try ILBMDecoder.decode(Self.form([Self.bmhd(width: 0, height: 1, planes: 1), Self.chunk("BODY", [])]))
        }
        #expect(throws: OwnDecodeError.unsupported) {
            try ILBMDecoder.decode(Self.form([Self.bmhd(width: 1, height: 1, planes: 12), Self.chunk("BODY", [])]))
        }
        #expect(throws: OwnDecodeError.notThisFormat) { try ILBMDecoder.decode(Self.form([], kind: "8SVX")) }
    }

    /// 65535 × 65535 (BMHD's sides are 16 bits) claimed in the header: refused as corrupt before anything is allocated.
    @Test func hugeHeaderIsRefused() {
        let data = Self.form([Self.bmhd(width: 65535, height: 65535, planes: 1), Self.chunk("BODY", [0, 0])])
        #expect(throws: OwnDecodeError.corrupt) { try ILBMDecoder.size(data) }
        #expect(throws: OwnDecodeError.corrupt) { try ILBMDecoder.decode(data) }
    }
}
