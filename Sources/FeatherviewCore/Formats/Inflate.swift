import Compression

/// zlib, gzip and raw DEFLATE, always to a size known in advance, so a corrupt or hostile
/// stream can't inflate without bound.
// shortcut: the Adler-32 / CRC-32 trailers aren't checked (a corrupt stream almost always fails to inflate to the exact size), check them if a file decodes to garbage.
enum Inflate {
    /// RFC 1950: 2-byte header, deflate, Adler-32 trailer.
    static func zlib(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        try zlibHeader(bytes)
        return try raw(bytes.dropFirst(2), size: size)
    }

    /// RFC 1950 straight into `out`, which it must fill; a longer stream stops there (TIFF's padded strips).
    static func zlib(_ bytes: ArraySlice<UInt8>, filling out: UnsafeMutableBufferPointer<UInt8>) throws {
        try zlibHeader(bytes)
        guard bytes.count > 2, let dst = out.baseAddress else { throw OwnDecodeError.corrupt }
        let written = bytes.dropFirst(2).withUnsafeBufferPointer {
            compression_decode_buffer(dst, out.count, $0.baseAddress!, $0.count, nil, COMPRESSION_ZLIB)
        }
        guard written == out.count else { throw OwnDecodeError.corrupt }
    }

    static func zlibHeader(_ bytes: ArraySlice<UInt8>) throws {
        guard bytes.count >= 2 else { throw OwnDecodeError.truncated }
        let cmf = Int(bytes[bytes.startIndex]), flg = Int(bytes[bytes.startIndex + 1])
        guard (cmf * 256 + flg) % 31 == 0, cmf & 0x0F == 8, cmf >> 4 <= 7, flg & 0x20 == 0
        else { throw OwnDecodeError.corrupt }
    }

    /// RFC 1952 member: header with optional FEXTRA / FNAME / FCOMMENT / FHCRC, deflate, CRC-32 and size.
    static func gzip(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        var i = bytes.startIndex
        func need(_ n: Int) throws { guard bytes.endIndex - i >= n else { throw OwnDecodeError.truncated } }
        func skipZeroTerminated() throws {
            while true { try need(1); i += 1; if bytes[i - 1] == 0 { return } }
        }
        try need(10)
        guard bytes[i] == 0x1F, bytes[i + 1] == 0x8B, bytes[i + 2] == 8 else { throw OwnDecodeError.corrupt }
        let flags = bytes[i + 3]
        i += 10
        if flags & 0x04 != 0 {
            try need(2)
            let extra = Int(bytes[i]) | Int(bytes[i + 1]) << 8
            i += 2
            try need(extra)
            i += extra
        }
        if flags & 0x08 != 0 { try skipZeroTerminated() }
        if flags & 0x10 != 0 { try skipZeroTerminated() }
        if flags & 0x02 != 0 { try need(2); i += 2 }
        return try raw(bytes[i...], size: size)
    }

    /// RFC 1951. Apple's `COMPRESSION_ZLIB` is raw DEFLATE without the zlib wrapper.
    static func raw(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        guard size >= 0, !bytes.isEmpty else { throw OwnDecodeError.corrupt }
        // One byte of room past `size`: filling it means the stream holds more than expected.
        var out = [UInt8](repeating: 0, count: size + 1)
        let written = bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        // 0 is also what the function returns on error, so a zero size passes only for an empty result.
        guard written == size else { throw OwnDecodeError.corrupt }
        out.removeLast()
        return out
    }
}
