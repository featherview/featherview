import Foundation

/// X11 (and X10) bitmaps: C source with `#define name_width N`, `#define name_height N` and an array of
/// bytes (or 16-bit words for X10), least significant bit first, each row padded to whole units.
enum XBMDecoder {
    static let format = OwnFormat.raster(name: "XBM", extensions: ["xbm"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        try header(stripCComments(String(decoding: data, as: UTF8.self)))
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let text = stripCComments(String(decoding: data, as: UTF8.self))
        let (width, height) = try header(text)
        guard let open = text.firstIndex(of: "{") else { throw OwnDecodeError.truncated }
        let unitBits = text[..<open].contains("short") ? 16 : 8
        let body = text[text.index(after: open)...].prefix { $0 != "}" }
        var units: [Int] = []
        for token in body.split(separator: ",") {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { continue }
            guard let value = cInteger(token), value < 1 << unitBits else { throw OwnDecodeError.corrupt }
            units.append(value)
        }
        let unitsPerRow = (width + unitBits - 1) / unitBits
        guard units.count >= unitsPerRow * height else { throw OwnDecodeError.truncated }
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where units[y * unitsPerRow + x / unitBits] >> (x % unitBits) & 1 == 0 {
                image[x, y] = (255, 255, 255, 255)
            }
        }
        return image
    }

    private static func header(_ text: String) throws -> (width: Int, height: Int) {
        var width: Int?, height: Int?
        for line in text.split(whereSeparator: \.isNewline) {
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

/// Replaces `/* */` and `//` comments with a space, leaving string literals alone.
func stripCComments(_ text: String) -> String {
    var out = "", chars = Array(text), i = 0, inString = false
    while i < chars.count {
        let c = chars[i], next = i + 1 < chars.count ? chars[i + 1] : nil
        if inString {
            out.append(c)
            if c == "\\", let next { out.append(next); i += 1 } else if c == "\"" { inString = false }
            i += 1
        } else if c == "/", next == "*" {
            i += 2
            while i < chars.count, !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") { i += 1 }
            i += 2
            out.append(" ")
        } else if c == "/", next == "/" {
            while i < chars.count, !chars[i].isNewline { i += 1 }
        } else {
            if c == "\"" { inString = true }
            out.append(c)
            i += 1
        }
    }
    return out
}
