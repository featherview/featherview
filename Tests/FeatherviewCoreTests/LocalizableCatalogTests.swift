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

    /// Commands and buttons are imperatives (Catalan "Desa", not "Desar"), with one word per command
    /// across the app (Danish "Gem" for Save and Save As).
    @Test func commandsUseOneImperativeTerm() throws {
        let catalog = try StringCatalog.load(StringCatalog.shippedURL)
        func value(_ key: String, _ language: String) -> String? {
            catalog.strings[key]?.localizations?[language]?.stringUnit?.value
        }
        let terms: [(String, String, String)] = [
            ("da", "Save", "Gem"), ("da", "Save As…  (S)", "Gem som…  (S)"),
            ("ca", "Cancel", "Cancel·la"), ("ca", "Save", "Desa"), ("ca", "Save As…  (S)", "Desa com a…  (S)"),
            ("ca", "Close", "Tanca"), ("ca", "Delete", "Elimina"), ("ca", "Copy", "Copia"), ("ca", "Cut", "Retalla"),
            ("ca", "Paste", "Enganxa"), ("ca", "Select All", "Selecciona-ho tot"), ("ca", "Open With", "Obre amb"),
            ("ca", "Customize Toolbar…", "Personalitza la barra d’eines…"), ("ca", "Hide Toolbar", "Oculta la barra d’eines"),
            ("ca", "Show Toolbar", "Mostra la barra d’eines"), ("ca", "Replace", "Substitueix"), ("ca", "Quit", "Surt"),
            ("ca", "Keep", "Mantén"), ("ca", "Move", "Mou"), ("ca", "Remove", "Treu"), ("ca", "Choose…", "Tria…"), ("ca", "Rename", "Canvia el nom"),
        ]
        for (language, key, term) in terms { #expect(value(key, language) == term, "\(language): \(key)") }
        #expect(value("Save As and the batch window start with these options for each format.", "da")?.hasPrefix("Gem som") == true)
        #expect(value("Save As and the batch window start with these options for each format.", "ca")?.hasPrefix("Desa com a") == true)
    }

    /// Translations use characters a translator types: a plain hyphen, not U+2011.
    @Test func translationsUsePlainHyphens() throws {
        let text = try String(contentsOf: StringCatalog.shippedURL, encoding: .utf8)
        #expect(!text.contains("\u{2011}"))
    }

    /// In any other formatting, the next sync or Xcode save rewrites every line and buries the real change.
    @Test func catalogKeepsXcodeFormatting() throws {
        let text = try String(contentsOf: StringCatalog.shippedURL, encoding: .utf8)
        #expect(text.hasPrefix("{\n  \"sourceLanguage\" : \"en\",\n"))
        #expect(!text.contains("\": "), "a line uses `\"key\": value` instead of Xcode's `\"key\" : value`")
    }
}
