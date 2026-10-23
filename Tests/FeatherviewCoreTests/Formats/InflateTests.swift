import Compression
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct InflateTests {
    static let sample: [UInt8] = (0..<5000).map { UInt8(truncatingIfNeeded: $0 * 7 + $0 / 13) }

    /// Raw DEFLATE (RFC 1951): what `COMPRESSION_ZLIB` writes.
    static func deflate(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 1024)
        let n = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        precondition(n > 0)
        return Array(out[0..<n])
    }

    static func adler32(_ bytes: [UInt8]) -> [UInt8] {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let v = b << 16 | a
        return [UInt8(v >> 24), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }

    static func zlib(_ bytes: [UInt8]) -> [UInt8] { [0x78, 0x9C] + deflate(bytes) + adler32(bytes) }


    /// A gzip member; the CRC isn't checked by `Inflate`, so zeros stand in for it.
    static func gzip(_ bytes: [UInt8], fileName: String? = nil) -> [UInt8] {
        let flags: UInt8 = fileName == nil ? 0 : 0x08
        var header: [UInt8] = [0x1F, 0x8B, 8, flags, 0, 0, 0, 0, 0, 3]
        if let fileName { header += Array(fileName.utf8) + [0] }
        return header + deflate(bytes) + [0, 0, 0, 0] + Fixtures.le32(bytes.count)
    }

    @Test func zlibRoundTrip() throws {
        let packed = Self.zlib(Self.sample)
        #expect(try Inflate.zlib(packed[...], size: Self.sample.count) == Self.sample)
    }

    @Test func gzipRoundTrip() throws {
        #expect(try Inflate.gzip(Self.gzip(Self.sample)[...], size: Self.sample.count) == Self.sample)
    }

    @Test func gzipWithFileNameField() throws {
        let packed = Self.gzip(Self.sample, fileName: "layer.bin")
        #expect(try Inflate.gzip(packed[...], size: Self.sample.count) == Self.sample)
    }

    @Test func rawRoundTrip() throws {
        #expect(try Inflate.raw(Self.deflate(Self.sample)[...], size: Self.sample.count) == Self.sample)
    }

    @Test func slicesNotStartingAtZeroWork() throws {
        let packed = [1, 2, 3] + Self.zlib(Self.sample)
        #expect(try Inflate.zlib(packed[3...], size: Self.sample.count) == Self.sample)
    }

    @Test func inflateRefusesMoreThanExpected() {
        let zeros = [UInt8](repeating: 0, count: 1 << 20)
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.raw(Self.deflate(zeros)[...], size: 1000) }
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib(Self.zlib(zeros)[...], size: 1000) }
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.gzip(Self.gzip(zeros)[...], size: 1000) }
    }

    @Test func inflateRefusesLessThanExpected() {
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib(Self.zlib(Self.sample)[...], size: Self.sample.count + 1) }
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.raw(Self.deflate(Self.sample)[...], size: Self.sample.count * 2) }
    }

    @Test func badZlibHeaderThrows() {
        let body = Array(Self.zlib(Self.sample).dropFirst(2))
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib(([0x78, 0x9D] + body)[...], size: Self.sample.count) } // check bits
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib(([0x77, 0x85] + body)[...], size: Self.sample.count) } // CM 7
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib(([0x78, 0xBB] + body)[...], size: Self.sample.count) } // FDICT
        #expect(throws: OwnDecodeError.truncated) { try Inflate.zlib([0x78][...], size: 1) }
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.zlib([0x78, 0x9C][...], size: 1) } // no stream at all
    }

    @Test func badGzipMagicThrows() {
        var packed = Self.gzip(Self.sample)
        packed[1] = 0x8C
        #expect(throws: OwnDecodeError.corrupt) { try Inflate.gzip(packed[...], size: Self.sample.count) }
        #expect(throws: OwnDecodeError.truncated) { try Inflate.gzip([0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 3, 65][...], size: 1) }
    }
}
