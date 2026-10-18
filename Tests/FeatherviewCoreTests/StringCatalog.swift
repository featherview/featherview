import Foundation
@testable import FeatherviewCore

/// Resources/Localizable.xcstrings as the tests read it, with the checks a translation must pass.
struct StringCatalog: Decodable {
    struct Entry: Decodable {
        var extractionState: String?
        var shouldTranslate: Bool?
        var localizations: [String: Localization]?
    }
    struct Localization: Decodable {
        var stringUnit: StringUnit?
        var variations: Variations?
        var substitutions: [String: Substitution]?
    }
    struct StringUnit: Decodable {
        var state: String?
        var value: String?
    }
    struct Variations: Decodable {
        var plural: [String: Localization]?
    }
    struct Substitution: Decodable {
        var argNum: Int?
        var formatSpecifier: String
        var variations: Variations
    }

    var sourceLanguage: String
    var strings: [String: Entry]

    /// The app's languages (spec order), "en" first; Info.plist's CFBundleLocalizations.
    static let languages = [
        "en", "zh-Hans", "zh-Hant", "hi", "es", "ar", "fr", "pt-BR", "ru", "id", "de", "ja", "tr", "vi", "ko",
        "it", "th", "pl", "uk", "ms", "nl", "ro", "el", "hu", "sv", "cs", "ca", "he", "da", "fi",
    ]

    static let shippedURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/Localizable.xcstrings")

    static func load(_ url: URL) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }

    static func decode(_ json: String) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(json.utf8))
    }

    var presentLanguages: Set<String> {
        strings.values.reduce(into: ["en"]) { $0.formUnion($1.localizations?.keys ?? [:].keys) }
    }

    /// One short sentence per problem, naming the key and language.
    func problems(languages: some Collection<String>) -> [String] {
        let translated = languages.filter { $0 != "en" }.sorted()
        var problems: [String] = []
        for key in strings.keys.sorted() {
            let entry = strings[key]!
            if entry.shouldTranslate == false {
                if Specifiers.stripped(key).contains(where: \.isLetter) {
                    problems.append("\"\(key)\" is marked not to translate but has words in it")
                }
                continue
            }
            if entry.extractionState == "stale" {
                problems.append("\"\(key)\" is stale: the app no longer uses it")
            }
            let en = entry.localizations?["en"]
            let source = en?.stringUnit?.value ?? en?.variations?.plural?["other"]?.stringUnit?.value ?? key
            for language in translated {
                guard let localization = entry.localizations?[language] else {
                    problems.append("\(language): \"\(key)\" has no translation")
                    continue
                }
                var check = Check(language: language, key: key, problems: [])
                check.localization(localization, source: source, en: en)
                problems += check.problems
            }
        }
        return problems
    }
}

private struct Check {
    let language: String
    let key: String
    var problems: [String]

    private var rightToLeft: Bool { language == "ar" || language == "he" }

    private mutating func report(_ problem: String) { problems.append("\(language): \"\(key)\" \(problem)") }

    mutating func localization(_ l: StringCatalog.Localization, source: String, en: StringCatalog.Localization?) {
        if let unit = l.stringUnit { leaf(unit, source: source, form: nil) }
        if let plural = l.variations?.plural {
            let counts = Specifiers(source).byIndex.values.filter { $0 == "integer" }.count
            if counts != 1 { report("has a plural for a source with \(counts) counts, use %#@name@ substitutions") }
            forms(plural, source: source, what: "plural")
        }
        for (name, substitution) in (l.substitutions ?? [:]).sorted(by: { $0.key < $1.key }) {
            let enSubstitution = en?.substitutions?[name]
            if let enSubstitution, substitution.argNum != enSubstitution.argNum
                || Specifiers.type(substitution.formatSpecifier) != Specifiers.type(enSubstitution.formatSpecifier) {
                report("has substitution \(name) for another argument than the source")
            }
            let enOther = enSubstitution?.variations.plural?["other"]?.stringUnit?.value
            forms(substitution.variations.plural ?? [:], source: enOther ?? source, what: "substitution \(name)")
        }
        // Only stringUnit and plural are checked; any other variations (device) count as no text.
        if l.stringUnit == nil && l.variations?.plural == nil { report("has no text") }
        let texts = [l.stringUnit?.value] + (l.variations?.plural ?? [:]).values.map { $0.stringUnit?.value }
        let used = texts.compactMap { $0 }.reduce(into: Set<String>()) { $0.formUnion(Specifiers($1).tokens) }
        for name in used.sorted() where l.substitutions?[name] == nil { report("has no substitution for %#@\(name)@") }
    }

    private mutating func forms(_ forms: [String: StringCatalog.Localization], source: String, what: String) {
        if forms["other"] == nil { report("has no \"other\" form in its \(what)") }
        for (form, localization) in forms.sorted(by: { $0.key < $1.key }) {
            guard let unit = localization.stringUnit else { report("has no text in its \(form) form"); continue }
            leaf(unit, source: source, form: form)
        }
    }

    private mutating func leaf(_ unit: StringCatalog.StringUnit, source: String, form: String?) {
        let place = form.map { " in its \($0) form" } ?? ""
        guard let text = unit.value, !text.isEmpty else { report("has no text\(place)"); return }
        if unit.state != "translated" { report("is \(unit.state ?? "without a state")\(place), not translated") }

        let want = Specifiers(source)
        // A source without arguments is never formatted: its % is text, even with a suffix ("%-a", "%'si").
        let have = want.byIndex.isEmpty && want.tokens.isEmpty ? want : Specifiers(text)
        // CLDR `one` also covers 0 (fr, pt-BR, hi) or 21, 31 … (ru, uk) there: only `other`'s count is right.
        let oneIsMore = ["fr", "pt-BR", "hi", "ru", "uk"].contains(language)
        let mayOmitCount = ["zero", "two"].contains(form ?? "") || form == "one" && !oneIsMore
        if have.tokens != want.tokens || !(have.byIndex == want.byIndex || mayOmitCount && want.omittingOneCount(is: have.byIndex)) {
            report("has \(have) where the source has \(want)\(place)")
        }
        if source.contains("Featherview") && !text.contains("Featherview") { report("lost the name Featherview\(place)") }
        menuKey(text, source: source, place: place)
        arrows(text, source: source, place: place)
        if Self.placeholders(text) != Self.placeholders(source) { report("changed a {placeholder}\(place)") }
    }

    private mutating func menuKey(_ text: String, source: String, place: String) {
        guard var want = MenuKey.parse(source) else { return }
        if rightToLeft {
            let swapped = ["\u{F702}": "\u{F703}", "\u{F703}": "\u{F702}"][want.key] ?? want.key
            want = MenuKey(title: want.title, key: swapped, modifiers: want.modifiers)
        }
        let have = MenuKey.parse(text)
        if have?.key != want.key || have?.modifiers != want.modifiers {
            report("lost its menu key, keep the \"  (…)\" hint as in the source\(place)")
        }
    }

    private mutating func arrows(_ text: String, source: String, place: String) {
        var (have, want) = (Self.arrowCounts(text), Self.arrowCounts(source))
        if rightToLeft { want.inside = (want.inside.1, want.inside.0) }
        if have.inside != want.inside { report("has ← → in its (…) hint that don't follow the screen's direction\(place)") }
        if have.outside != want.outside { report("changed ← or → outside a (…) hint\(place)") }
    }

    /// (← count, → count) inside and outside parentheses.
    private static func arrowCounts(_ text: String) -> (inside: (Int, Int), outside: (Int, Int)) {
        var inside = (0, 0), outside = (0, 0), depth = 0
        for character in text {
            switch character {
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case "←": if depth > 0 { inside.0 += 1 } else { outside.0 += 1 }
            case "→": if depth > 0 { inside.1 += 1 } else { outside.1 += 1 }
            default: break
            }
        }
        return (inside, outside)
    }

    private static func placeholders(_ text: String) -> Set<String> {
        Set(text.matches(of: try! Regex(#"\{[a-z]+(?::\d+)?\}"#)).map { String(text[$0.range]) })
    }
}

/// A format string's arguments: printf specifiers by argument index (types normalized), `%#@name@` tokens,
/// and a substitution form's `%arg` (index 0).
private struct Specifiers: CustomStringConvertible {
    var byIndex: [Int: String] = [:]
    var tokens: Set<String> = []

    // nonisolated(unsafe): Regex isn't Sendable; these are read-only after init and never mutated.
    // No space flag: "% of the shorter side" is a percent sign, not "% o".
    nonisolated(unsafe) private static let specifier =
        try! Regex(#"%arg|%(?:(\d+)\$)?[-+#0']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp])"#)
    nonisolated(unsafe) private static let token = try! Regex(#"%#@([A-Za-z0-9_]+)@"#)

    /// The text without its specifiers and tokens.
    static func stripped(_ text: String) -> String {
        text.replacingOccurrences(of: "%%", with: "").replacing(token, with: "").replacing(specifier, with: "")
    }

    init(_ text: String) {
        var rest = text.replacingOccurrences(of: "%%", with: "")
        for match in rest.matches(of: Self.token) {
            if let name = match.output[1].substring { tokens.insert(String(name)) }
        }
        rest.replace(Self.token, with: "")
        var next = 1
        for match in rest.matches(of: Self.specifier) {
            guard let type = match.output[2].substring else { byIndex[0] = "arg"; continue }
            let index = match.output[1].substring.flatMap { Int($0) } ?? next
            if match.output[1].substring == nil { next += 1 }
            let new = Self.type(String(type))
            // One argument used twice with two types never matches the source's one type.
            if let old = byIndex[index], old != new { byIndex[index] = "\(old) and \(new)" } else { byIndex[index] = new }
        }
    }

    /// A conversion's normalized type; also takes a substitution's formatSpecifier ("lld", "@").
    static func type(_ conversion: String) -> String {
        switch conversion.last {
        case "@": "object"
        case "d", "D", "i", "u", "U", "x", "X", "o", "O", "c", "C": "integer"
        case "f", "F", "e", "E", "g", "G", "a", "A": "double"
        default: conversion
        }
    }

    /// A zero/one/two form may leave out the plural's own count ("one file"): a substitution's %arg,
    /// or a whole-string plural's only integer.
    func omittingOneCount(is other: [Int: String]) -> Bool {
        let counts = byIndex[0] != nil ? [0] : byIndex.filter { $0.value == "integer" }.map(\.key)
        return counts.count == 1 && byIndex.filter { $0.key != counts[0] } == other
    }

    var description: String {
        let parts = byIndex.sorted { $0.key < $1.key }.map { $0.key == 0 ? "%arg" : "\($0.key): \($0.value)" }
            + tokens.sorted().map { "%#@\($0)@" }
        return parts.isEmpty ? "no arguments" : parts.joined(separator: ", ")
    }
}
