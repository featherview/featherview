import Foundation

/// X11 (and X10) bitmaps: C source with `#define name_width N`, `#define name_height N` and an array of
/// bytes (or 16-bit words for X10), least significant bit first, each row padded to whole units.
enum XBMDecoder {
    static let format = OwnFormat.raster(name: "XBM", extensions: ["xbm"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        try header(stripCComments(data, upTo: UInt8(ascii: "{")))
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let bytes = stripCComments(data)
        guard let open = bytes.firstIndex(of: UInt8(ascii: "{")) else {
            _ = try header(bytes)
            throw OwnDecodeError.truncated
        }
        let (width, height) = try header(bytes[..<open])
        // The C type word, not a substring: names like `short_arrow_bits` are X11 too.
        let unitBits = String(decoding: bytes[..<open], as: UTF8.self).contains(/\bshort\b/) ? 16 : 8
        let body = bytes[(open + 1)...].prefix { $0 != UInt8(ascii: "}") }
        let unitsPerRow = (width + unitBits - 1) / unitBits
        var units: [UInt16] = []
        units.reserveCapacity(unitsPerRow * height)
        for token in body.split(separator: UInt8(ascii: ","), omittingEmptySubsequences: false) {
            guard let first = token.firstIndex(where: { !isSpace($0) }) else { continue }
            let last = token.lastIndex(where: { !isSpace($0) })!
            guard let value = unit(token[first...last]), value < 1 << unitBits else { throw OwnDecodeError.corrupt }
            units.append(UInt16(value))
        }
        guard units.count >= unitsPerRow * height else { throw OwnDecodeError.truncated }
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where Int(units[y * unitsPerRow + x / unitBits]) >> (x % unitBits) & 1 == 0 {
                image[x, y] = (255, 255, 255, 255)
            }
        }
        return image
    }

    /// A C integer literal in bytes, decimal or 0x hex, up to 16 bits; nil if malformed or larger.
    private static func unit(_ token: ArraySlice<UInt8>) -> Int? {
        var digits = token[...], radix = 10
        if digits.count > 2, digits.first == UInt8(ascii: "0"), digits.dropFirst().first! | 0x20 == UInt8(ascii: "x") {
            digits = digits.dropFirst(2)
            radix = 16
        }
        var value = 0
        for byte in digits {
            let digit: Int
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Int(byte) - 48
            case UInt8(ascii: "a")...UInt8(ascii: "f"), UInt8(ascii: "A")...UInt8(ascii: "F"): digit = Int(byte | 0x20) - 87
            default: return nil
            }
            guard digit < radix else { return nil }
            value = value * radix + digit
            if value > 0xFFFF { return nil }
        }
        return value
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (0x09...0x0D).contains(byte) }

    private static func header(_ bytes: some Collection<UInt8>) throws -> (width: Int, height: Int) {
        var width: Int?, height: Int?
        for line in String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 3, words[0] == "#define" else { continue }
            if words[1].hasSuffix("_width") { width = cInteger(String(words[2])) ?? -1 }
            if words[1].hasSuffix("_height") { height = cInteger(String(words[2])) ?? -1 }
        }
        guard let width, let height else { throw OwnDecodeError.notThisFormat }
        return try checkedSize(width, height)
    }
}

/// A non-negative C integer literal, decimal or 0x hex; nil if malformed or too large for Int.
func cInteger(_ token: String) -> Int? {
    let lower = token.lowercased()
    return lower.hasPrefix("0x") ? Int(lower.dropFirst(2), radix: 16) : Int(lower)
}

/// Replaces `/* */` and `//` comments with a space, leaving string literals alone; bytes, not Characters,
/// so a large file costs one copy. With `stop`, ends before the first `stop` byte outside comments and strings.
func stripCComments(_ data: Data, upTo stop: UInt8? = nil) -> [UInt8] {
    let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
    var out: [UInt8] = [], i = data.startIndex, inString = false
    if stop == nil { out.reserveCapacity(data.count) }
    while i < data.endIndex {
        let c = data[i], next = i + 1 < data.endIndex ? data[i + 1] : nil
        if inString {
            out.append(c)
            if c == backslash, let next { out.append(next); i += 1 } else if c == quote { inString = false }
            i += 1
        } else if c == slash, next == star {
            i += 2
            while i < data.endIndex, !(data[i] == star && i + 1 < data.endIndex && data[i + 1] == slash) { i += 1 }
            i += 2
            out.append(0x20)
        } else if c == slash, next == slash {
            while i < data.endIndex, data[i] != 0x0A, data[i] != 0x0D { i += 1 }
        } else {
            if c == stop { break }
            if c == quote { inString = true }
            out.append(c)
            i += 1
        }
    }
    return out
}
