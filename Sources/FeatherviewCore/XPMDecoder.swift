import Foundation

/// XPM3 pixmaps: C source whose string literals are a "width height ncolors cpp" header, one line per
/// colour ("<chars> c <colour>"), then one line per pixel row of `cpp` characters per pixel.
enum XPMDecoder {
    static let format = OwnFormat.raster(name: "XPM", extensions: ["xpm"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        let header = try values(strings(in: [UInt8](data)))
        return (header.width, header.height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let lines = strings(in: [UInt8](data))
        let (width, height, colors, cpp) = try values(lines)
        // Not `1 + colors + height`: a huge colour count would overflow.
        guard lines.count - 1 - height >= colors else { throw OwnDecodeError.truncated }
        var palette: [UInt64: Pixel] = [:]
        for line in lines[1...colors] {
            guard line.count >= cpp else { throw OwnDecodeError.corrupt }
            palette[key(line[0..<cpp])] = color(String(decoding: line[cpp...], as: UTF8.self))
        }
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let row = lines[1 + colors + y]
            guard row.count >= width * cpp else { throw OwnDecodeError.truncated }
            for x in 0..<width {
                guard let pixel = palette[key(row[x * cpp..<(x + 1) * cpp])] else { throw OwnDecodeError.corrupt }
                image[x, y] = pixel
            }
        }
        return image
    }

    private static func values(_ lines: [[UInt8]]) throws -> (width: Int, height: Int, colors: Int, cpp: Int) {
        guard let first = lines.first else { throw OwnDecodeError.notThisFormat }
        let numbers = String(decoding: first, as: UTF8.self).split(whereSeparator: \.isWhitespace).prefix(4).map { Int($0) }
        guard numbers.count == 4 else { throw OwnDecodeError.notThisFormat }
        guard let width = numbers[0], let height = numbers[1], let colors = numbers[2], let cpp = numbers[3],
              colors > 0, (1...8).contains(cpp) else { throw OwnDecodeError.corrupt }  // 8 bytes fit a UInt64 key
        let size = try checkedSize(width, height)
        return (size.0, size.1, colors, cpp)
    }

    private static func key(_ chars: ArraySlice<UInt8>) -> UInt64 { chars.reduce(0) { $0 << 8 | UInt64($1) } }

    /// The contents of every C string literal, skipping comments.
    private static func strings(in bytes: [UInt8]) -> [[UInt8]] {
        var result: [[UInt8]] = [], i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "/"), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "*") {
                i += 2
                while i + 1 < bytes.count, !(bytes[i] == UInt8(ascii: "*") && bytes[i + 1] == UInt8(ascii: "/")) { i += 1 }
                i += 2
            } else if bytes[i] == UInt8(ascii: "\"") {
                var string: [UInt8] = []
                i += 1
                while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
                    if bytes[i] == UInt8(ascii: "\\"), i + 1 < bytes.count { i += 1 }
                    string.append(bytes[i])
                    i += 1
                }
                if i < bytes.count { result.append(string) }  // an unterminated string is dropped
                i += 1
            } else {
                i += 1
            }
        }
        return result
    }

    /// The colour for one colour line's keys; the colour visual ("c") wins over grey and mono ones.
    private static func color(_ spec: String) -> Pixel {
        var byKey: [String: String] = [:], current: String?
        for word in spec.split(whereSeparator: \.isWhitespace).map(String.init) {
            if ["c", "m", "g", "g4", "s"].contains(word) {
                current = word
                byKey[word] = ""
            } else if let current {
                byKey[current, default: ""] += byKey[current, default: ""].isEmpty ? word : " " + word
            }
        }
        guard let value = ["c", "g", "g4", "m"].lazy.compactMap({ byKey[$0] }).first(where: { !$0.isEmpty })
        else { return (0, 0, 0, 255) }
        return parse(value.lowercased())
    }

    private static func parse(_ value: String) -> Pixel {
        if value == "none" { return (0, 0, 0, 0) }
        if value.hasPrefix("#") {
            let hex = value.dropFirst()
            let digits = hex.count / 3
            guard hex.count % 3 == 0, (1...4).contains(digits), let all = UInt64(hex, radix: 16) else { return (0, 0, 0, 255) }
            // Each channel's top 8 bits; one-digit channels repeat ("f" is "ff").
            let channel = { (i: Int) -> UInt8 in
                let v = Int(all >> UInt64((2 - i) * digits * 4)) & ((1 << (digits * 4)) - 1)
                return UInt8(digits == 1 ? v * 17 : v >> ((digits - 2) * 4))
            }
            return (channel(0), channel(1), channel(2), 255)
        }
        let name = value.replacingOccurrences(of: " ", with: "")
        if let rgb = named[name] { return (rgb.0, rgb.1, rgb.2, 255) }
        for prefix in ["gray", "grey"] where name.hasPrefix(prefix) {
            if let percent = Int(name.dropFirst(prefix.count)), (0...100).contains(percent) {
                let v = UInt8((percent * 255 + 50) / 100)
                return (v, v, v, 255)
            }
        }
        return (0, 0, 0, 255)  // shortcut: a small X11 name table, unknown names are black; add rgb.txt if files need it
    }

    private static let named: [String: (UInt8, UInt8, UInt8)] = [
        "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "green": (0, 255, 0),
        "blue": (0, 0, 255), "yellow": (255, 255, 0), "cyan": (0, 255, 255), "magenta": (255, 0, 255),
        "gray": (190, 190, 190), "grey": (190, 190, 190),
    ]
}
