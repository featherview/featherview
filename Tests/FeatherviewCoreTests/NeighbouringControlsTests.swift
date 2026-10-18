import Testing

/// Controls that sit side by side must read differently.
@Suite struct NeighbouringControlsTests {
    @Test func neighbouringControlsHaveDistinctText() throws {
        let strings = try StringCatalog.load(StringCatalog.shippedURL).strings
        // Batch toolbar while running; the image-list bar's icon menus (VoiceOver labels); the Text step's anchor and placement rows.
        for (a, b) in [("Pause", "Stop"), ("Add", "More"), ("Position:", "Place:")] {
            for language in StringCatalog.languages where language != "en" {
                let textA = strings[a]?.localizations?[language]?.stringUnit?.value
                let textB = strings[b]?.localizations?[language]?.stringUnit?.value
                #expect(textA != nil, "\(language): \"\(a)\" missing")
                if let textA { #expect(textA != textB, "\(language): \"\(a)\" and \"\(b)\" both read \(textA)") }
            }
        }
    }
}
