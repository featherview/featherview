import Testing
@testable import FeatherviewCore

/// Hand-built LZO1X streams, one per instruction class.
@Suite struct LZO1XTests {
    static let end: [UInt8] = [0x11, 0, 0]
    static let abcd = Array("abcd".utf8)

    @Test func firstByteLiteralRun() throws {
        #expect(try LZO1X.decompress([17 + 5] + Array("hello".utf8) + Self.end, size: 5) == Array("hello".utf8))
        #expect(try LZO1X.decompress([17 + 2] + Array("hi".utf8) + Self.end, size: 2) == Array("hi".utf8))
    }

    @Test func longLiteralRuns() throws {
        // Opcode 0..15 with nothing copied before: 3 + L literals, L = 0 extends with zero bytes (255 each).
        let eight = (0..<8).map { UInt8($0) }
        #expect(try LZO1X.decompress([5] + eight + Self.end, size: 8) == eight)
        let long = (0..<274).map { UInt8($0 & 0xFF) }
        #expect(try LZO1X.decompress([0, 0, 1] + long + Self.end, size: 274) == long)
    }

    @Test func shortMatchesWithinTwoKiB() throws {
        // 1 L L D D D S S: 5 + L bytes from (H << 3) + D + 1 back, then S literals.
        let five = try LZO1X.decompress([17 + 4] + Self.abcd + [0x80 | 1 << 5 | 3 << 2 | 2, 0] + Array("xy".utf8) + Self.end, size: 12)
        #expect(five == Array("abcdabcdabxy".utf8))
        // 0 1 L D D D S S: 3 + L bytes.
        let three = try LZO1X.decompress([17 + 4] + Self.abcd + [0x40 | 1 << 5 | 1 << 2, 0] + Self.end, size: 8)
        #expect(three == Array("abcdcdcd".utf8))
    }

    @Test func matchesWithinSixteenKiB() throws {
        // 0 0 1 L L L L L + LE16 (distance - 1) << 2 | S; L = 0 extends.
        let short = try LZO1X.decompress([17 + 4] + Self.abcd + [0x20 | 2, 3 << 2, 0] + Self.end, size: 8)
        #expect(short == Array("abcdabcd".utf8))
        let long = try LZO1X.decompress([17 + 4] + Self.abcd + [0x20, 1, 0, 0] + Self.end, size: 4 + 34)
        #expect(long == Self.abcd + [UInt8](repeating: UInt8(ascii: "d"), count: 34))
    }

    @Test func matchesBeyondSixteenKiB() throws {
        // 0 0 0 1 H L L L + LE16: distance 16384 + (H << 14) + (D >> 2); 16384 itself ends the stream.
        let head = (0..<16_400).map { UInt8($0 % 251) }
        let out = try LZO1X.decompress(Self.longLiteral(head) + [0x10 | 2, 1 << 2, 0] + Self.end, size: head.count + 4)
        #expect(Array(out[head.count...]) == Array(head[head.count - 16_385..<head.count - 16_385 + 4]))
    }

    @Test func twoAndThreeByteMatchesAfterLiterals() throws {
        // After 1..3 literals, 0 0 0 0 D D S S + H copies 2 bytes from (H << 2) + D + 1 back.
        let two = try LZO1X.decompress([17 + 4] + Self.abcd + [0x40 | 1 << 2 | 1, 0, UInt8(ascii: "z"), 1 << 2, 0] + Self.end, size: 10)
        #expect(two == Array("abcdcdczcz".utf8))
        // After 4 or more literals, the same opcode copies 3 bytes from (H << 2) + D + 2049 back.
        let head = (0..<2100).map { UInt8($0 % 249) }
        let out = try LZO1X.decompress(Self.longLiteral(head) + [1 << 2, 0] + Self.end, size: head.count + 3)
        #expect(Array(out[head.count...]) == Array(head[head.count - 2050..<head.count - 2047]))
    }

    @Test func badStreamsThrowAndNeverOverrun() {
        let good: [UInt8] = [17 + 4] + Self.abcd + [0x80 | 1 << 5 | 3 << 2, 0] + Self.end
        #expect(throws: OwnDecodeError.self) { try LZO1X.decompress(Array(good.dropLast()), size: 10) }  // truncated
        #expect(throws: OwnDecodeError.self) { try LZO1X.decompress(good, size: 9) }  // overruns the size
        #expect(throws: OwnDecodeError.self) { try LZO1X.decompress(good, size: 11) }  // ends short
        #expect(throws: OwnDecodeError.self) { try LZO1X.decompress([17 + 1, 1, 0x80 | 7 << 2, 9] + Self.end, size: 7) }  // distance before start
        #expect(throws: OwnDecodeError.self) { try LZO1X.decompress([], size: 1) }
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let junk = (0..<Int.random(in: 0..<40, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            if let out = try? LZO1X.decompress(junk, size: 64) { #expect(out.count == 64) }
        }
    }

    /// A long-literal opcode (state 0) carrying `bytes` (at least 19).
    static func longLiteral(_ bytes: [UInt8]) -> [UInt8] {
        var n = bytes.count - 3 - 15, ext: [UInt8] = [0]
        while n > 255 { ext.append(0); n -= 255 }
        return ext + [UInt8(n)] + bytes
    }
}
