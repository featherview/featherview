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
            "Apps for ⌥1, ⌥2 and ⌥3", "Appearance:", "System", "Light", "Dark",
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
}
