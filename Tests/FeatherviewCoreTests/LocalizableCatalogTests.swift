import Foundation
import Testing

/// UI text only reaches translators once scripts/strings.sh has put it into the catalog.
@Suite struct LocalizableCatalogTests {
    @Test func preferencesTextIsInTheCatalog() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = Set((catalog?["strings"] as? [String: Any] ?? [:]).keys)
        let expected = [
            "Folders", "After a move or Move to Trash", "Window", "Bars", "Overlay", "Pointer",
            "Apps for ⌥1, ⌥2 and ⌥3", "Appearance", "System", "Light", "Dark",
            "Hide toolbar and status bar while viewing",
        ]
        for key in expected { #expect(keys.contains(key), "missing \(key)") }
        // The background colour presets the Appearance setting replaced.
        for key in ["Background:", "Graphite", "Black", "Grey", "White", "Custom…", "Custom colour:"] {
            #expect(!keys.contains(key), "leftover \(key)")
        }
    }

    @Test func emptyWindowHintIsInTheCatalog() throws {
        let keys = Set(try StringCatalog.load(StringCatalog.shippedURL).strings.keys)
        #expect(keys.contains("Open an image or drop a folder here"))
        #expect(!keys.contains("Open an image with ⌘O, or drop one here"))
    }

    /// Controls that sit side by side must read differently in every language.
    @Test func neighbouringControlsHaveDistinctText() throws {
        let strings = try StringCatalog.load(StringCatalog.shippedURL).strings
        // Batch toolbar while running; the image-list bar's icon menus (VoiceOver labels); the Text step's anchor and placement rows.
        for (a, b) in [("Pause", "Stop"), ("Add", "More"), ("Position:", "Place:")] {
            for language in StringCatalog.languages where language != "en" {
                let textA = strings[a]?.localizations?[language]?.stringUnit?.value
                let textB = strings[b]?.localizations?[language]?.stringUnit?.value
                if let textA { #expect(textA != textB, "\(language): \"\(a)\" and \"\(b)\" both read \(textA)") }
            }
        }
    }
}
