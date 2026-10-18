import Foundation

/// Text on the disk image's background. The app never shows it; it is here so the string catalog carries it.
public enum DiskImageText {
    public static let firstOpenHelp = String(localized: "First open: open Featherview once from Applications. When macOS says it can't check it, go to System Settings › Privacy & Security and click Open Anyway. After that it opens normally.")

    /// The translation in an app's `Localizable.strings` (English text as the key), or the English text.
    public static func firstOpenHelp(from strings: [String: String]) -> String {
        strings[firstOpenHelp] ?? firstOpenHelp
    }
}
