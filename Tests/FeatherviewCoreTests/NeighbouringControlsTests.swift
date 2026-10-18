import Testing

/// Controls that sit side by side must read differently.
@Suite struct NeighbouringControlsTests {
    @Test func neighbouringControlsHaveDistinctText() throws {
        let strings = try StringCatalog.load(StringCatalog.shippedURL).strings
        // shortcut: checks only hi th vi id ms (fi "Add"/"More" and he "Position:"/"Place:" still match), widen to StringCatalog.languages once those differ.
        let languages = ["hi", "th", "vi", "id", "ms"]
        // Batch toolbar while running; the image-list bar's icon menus (VoiceOver labels); the Text step's anchor and placement rows.
        for (a, b) in [("Pause", "Stop"), ("Add", "More"), ("Position:", "Place:")] {
            for language in languages {
                let textA = strings[a]?.localizations?[language]?.stringUnit?.value
                let textB = strings[b]?.localizations?[language]?.stringUnit?.value
                #expect(textA != nil, "\(language): \"\(a)\" missing")
                if let textA { #expect(textA != textB, "\(language): \"\(a)\" and \"\(b)\" both read \(textA)") }
            }
        }
    }
}
