import Foundation

/// Text on the disk image's background. The app never shows it; it is here so the string catalog carries it.
public enum DiskImageText {
    public static let firstOpenHelp = String(localized: "Before the first open: double-click “Read Me First”. Featherview isn’t notarized by Apple yet, so macOS blocks it once. The file has the one line to paste into Terminal that lets it open, on any account.")

    /// The translation in an app's `Localizable.strings` (English text as the key), or the English text.
    public static func firstOpenHelp(from strings: [String: String]) -> String {
        strings[firstOpenHelp] ?? firstOpenHelp
    }

    /// Right-to-left only when the help is actually translated; the English fallback stays left-to-right.
    public static func helpIsRightToLeft(language: String, strings: [String: String]) -> Bool {
        strings[firstOpenHelp] != nil && Locale.Language(identifier: language).characterDirection == .rightToLeft
    }
}
