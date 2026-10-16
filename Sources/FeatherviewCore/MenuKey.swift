/// A viewer key written in a menu title, "Open…  (O)", so the menu can show it in its shortcut column.
/// Keys are AppKit key-equivalent characters (function keys in the U+F700 range).
public struct MenuKey: Equatable, Sendable {
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    public let title: String
    public let key: String
    public let modifiers: Modifiers

    public init(title: String, key: String, modifiers: Modifiers) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
    }

    /// The title without its "  (…)" part and the first key in it without modifiers (else the first key);
    /// nil when the title names no key.
    public static func parse(_ title: String) -> MenuKey? {
        guard title.hasSuffix(")"), let open = title.range(of: "  (", options: .backwards) else { return nil }
        let inside = title[open.upperBound..<title.index(before: title.endIndex)]
        let keys = inside.components(separatedBy: " or ").compactMap(key)
        guard let chosen = keys.first(where: { $0.modifiers.isEmpty }) ?? keys.first else { return nil }
        return MenuKey(title: String(title[..<open.lowerBound]), key: chosen.key, modifiers: chosen.modifiers)
    }

    private static let symbols: [Character: Modifiers] = ["⌘": .command, "⇧": .shift, "⌥": .option, "⌃": .control]
    private static let named: [String: String] = [
        "→": "\u{F703}", "←": "\u{F702}", "↑": "\u{F700}", "↓": "\u{F701}", "⌦": "\u{F728}", "⌫": "\u{8}",
        "Space": " ", "−": "-",
    ]

    private static func key(_ text: String) -> (key: String, modifiers: Modifiers)? {
        var modifiers: Modifiers = []
        var rest = Substring(text)
        while let first = rest.first, let modifier = symbols[first] {
            modifiers.insert(modifier)
            rest = rest.dropFirst()
        }
        let name = String(rest)
        if let key = named[name] { return (key, modifiers) }
        if name.count == 1 { return (name.lowercased(), modifiers) }
        // F1–F12 sit at U+F704 onwards.
        if name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...12).contains(number),
           let scalar = Unicode.Scalar(0xF703 + number) {
            return (String(Character(scalar)), modifiers)
        }
        return nil
    }
}
