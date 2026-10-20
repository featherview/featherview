/// LZO1X decompression to an exact size known in advance: a corrupt or hostile stream throws instead
/// of reading or writing out of bounds.
///
/// The stream is a sequence of instructions; each copies a match from the output written so far, then
/// 0...3 literals (its two low bits, "S"). How an opcode 0...15 reads depends on the literals the last
/// instruction copied ("state": 0, 1...3, or 4 for four or more):
/// - first byte 18...255: copy byte − 17 literals.
/// - 0...15, state 0: 3 + L literals; L = 0 extends: each zero byte adds 255, then 15 + the next byte.
/// - 0000DDSS H, state 1...3: 2 bytes from (H << 2) + D + 1 back; state 4: 3 bytes from (H << 2) + D + 2049 back.
/// - 0001HLLL + LE16: 2 + L bytes (L = 0 extends from 7) from 16384 + (H << 14) + (LE16 >> 2) back;
///   a distance of exactly 16384 ends the stream.
/// - 001LLLLL + LE16: 2 + L bytes (L = 0 extends from 31) from (LE16 >> 2) + 1 back.
/// - 01LDDDSS H: 3 + L bytes; 1LLDDDSS H: 5 + L bytes; both from (H << 3) + D + 1 back.
/// LE16's low two bits are S.
enum LZO1X {
    static func decompress(_ input: [UInt8], size: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: size)
        try input.withUnsafeBufferPointer { src in
            try output.withUnsafeMutableBufferPointer { dst in
                var ip = 0, op = 0
                func byte() throws -> Int {
                    guard ip < src.count else { throw OwnDecodeError.truncated }
                    ip += 1
                    return Int(src[ip - 1])
                }
                func le16() throws -> Int { try byte() | (try byte() << 8) }
                func extended(_ base: Int) throws -> Int {
                    var n = base
                    while true {
                        let b = try byte()
                        if b != 0 { return n + b }
                        n += 255
                    }
                }
                func literals(_ n: Int) throws {
                    guard n <= src.count - ip else { throw OwnDecodeError.truncated }
                    guard n <= size - op else { throw OwnDecodeError.corrupt }
                    for i in 0..<n { dst[op + i] = src[ip + i] }
                    ip += n
                    op += n
                }
                func match(_ distance: Int, _ length: Int) throws {
                    guard distance <= op, length <= size - op else { throw OwnDecodeError.corrupt }
                    // Byte by byte: an overlapping match repeats what it just wrote.
                    for i in op..<op + length { dst[i] = dst[i - distance] }
                    op += length
                }

                var state = 0
                if src.first.map({ $0 > 17 }) == true {
                    let n = try byte() - 17
                    try literals(n)
                    state = min(n, 4)
                }
                while true {
                    let t = try byte()
                    let s: Int
                    switch t {
                    case 0..<16 where state == 0:
                        try literals((t == 0 ? try extended(15) : t) + 3)
                        state = 4
                        continue
                    case 0..<16:
                        let h = try byte()
                        try state == 4 ? match((h << 2) + (t >> 2) + 2049, 3) : match((h << 2) + (t >> 2) + 1, 2)
                        s = t & 3
                    case 16..<32:
                        let length = (t & 7 == 0 ? try extended(7) : t & 7) + 2
                        let d = try le16()
                        let distance = 16384 + ((t & 8) << 11) + (d >> 2)
                        if distance == 16384 {
                            guard op == size else { throw OwnDecodeError.corrupt }
                            return
                        }
                        try match(distance, length)
                        s = d & 3
                    case 32..<64:
                        let length = (t & 31 == 0 ? try extended(31) : t & 31) + 2
                        let d = try le16()
                        try match((d >> 2) + 1, length)
                        s = d & 3
                    case 64..<128:
                        try match((try byte() << 3) + (t >> 2 & 7) + 1, 3 + (t >> 5 & 1))
                        s = t & 3
                    default:
                        try match((try byte() << 3) + (t >> 2 & 7) + 1, 5 + (t >> 5 & 3))
                        s = t & 3
                    }
                    try literals(s)
                    state = s
                }
            }
        }
        return output
    }
}
