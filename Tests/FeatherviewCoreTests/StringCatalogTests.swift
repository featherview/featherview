import Foundation
import Testing

/// The checks every translation must pass before it ships (plan milestone 6, Task 4).
@Suite struct StringCatalogTests {
    /// A one-key catalog: `en` (optional) and one translation, each a localization object.
    private func catalog(
        _ key: String, en: [String: Any]? = nil, _ language: String, _ translation: [String: Any]?,
        entry extra: [String: Any] = [:]
    ) throws -> StringCatalog {
        var localizations: [String: Any] = [:]
        if let en { localizations["en"] = en }
        if let translation { localizations[language] = translation }
        var entry = extra
        if !localizations.isEmpty { entry["localizations"] = localizations }
        let json: [String: Any] = ["sourceLanguage": "en", "version": "1.0", "strings": [key: entry]]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try StringCatalog.decode(String(decoding: data, as: UTF8.self))
    }

    private func unit(_ value: String, _ state: String = "translated") -> [String: Any] {
        ["stringUnit": ["state": state, "value": value]]
    }

    private func plural(_ forms: [String: String]) -> [String: Any] {
        ["variations": ["plural": forms.mapValues { unit($0) }]]
    }

    private func problems(_ catalog: StringCatalog, _ language: String) -> [String] {
        catalog.problems(languages: ["en", language])
    }

    @Test func completeCatalogHasNoProblems() throws {
        let c = try catalog("Can't open %@", "de", unit("%@ lässt sich nicht öffnen"))
        #expect(problems(c, "de") == [])
    }

    @Test func missingLanguageIsReported() throws {
        let c = try catalog("Open…", "de", nil)
        #expect(problems(c, "de").count == 1)
    }

    @Test func emptyTranslationIsReported() throws {
        let c = try catalog("Open…", "de", unit(""))
        #expect(problems(c, "de").count == 1)
    }

    @Test func untranslatedStateIsReported() throws {
        let c = try catalog("Open…", "de", unit("Öffnen…", "needs_review"))
        #expect(problems(c, "de").count == 1)
    }

    @Test func mismatchedSpecifierIsReported() throws {
        let c = try catalog("Can't open %@", "de", unit("%lld lässt sich nicht öffnen"))
        #expect(problems(c, "de").count == 1)
    }

    @Test func positionalSpecifiersMatchByIndex() throws {
        let good = try catalog("%@ in %lld", "de", unit("%2$lld: %1$@"))
        #expect(problems(good, "de") == [])
        let swapped = try catalog("%@ in %lld", "de", unit("%2$@: %1$lld"))
        #expect(problems(swapped, "de").count == 1)
    }

    @Test func positionalArgumentUsedTwiceWithAnotherTypeIsReported() throws {
        let c = try catalog("%@ in %lld", "de", unit("%1$@ %2$@ in %2$lld"))
        #expect(problems(c, "de").count == 1)
    }

    @Test func percentSignInArgumentFreeSourceIsText() throws {
        let hu = try catalog("% of the shorter side", "hu", unit("a rövidebb oldal %-a"))
        #expect(problems(hu, "hu") == [])
        let tr = try catalog("% of the shorter side", "tr", unit("kısa kenarın %'si"))
        #expect(problems(tr, "tr") == [])
    }

    @Test func pluralOneMayOmitCount() throws {
        let en = plural(["one": "%lld file", "other": "%lld files"])
        let good = try catalog("%lld files", en: en, "ar", plural(["one": "ملف واحد", "other": "%lld ملفات"]))
        #expect(problems(good, "ar") == [])
        let bad = try catalog("%lld files", en: en, "ar", plural(["one": "ملف واحد", "other": "ملفات"]))
        #expect(problems(bad, "ar").count == 1)
    }

    @Test func pluralWithoutOtherIsReported() throws {
        let en = plural(["one": "%lld file", "other": "%lld files"])
        let c = try catalog("%lld files", en: en, "de", plural(["one": "%lld Datei"]))
        #expect(problems(c, "de").count == 1)
    }

    @Test func brandNameMustStay() throws {
        #expect(problems(try catalog("About Featherview", "de", unit("Über Featherview")), "de") == [])
        #expect(problems(try catalog("About Featherview", "de", unit("Über Federblick")), "de").count == 1)
    }

    @Test func menuKeyHintMustStay() throws {
        let key = "Next  (→ or Space)"
        #expect(problems(try catalog(key, "de", unit("Weiter  (→ oder Leertaste)")), "de").count == 1)
        #expect(problems(try catalog(key, "de", unit("Weiter  (→ or Space)")), "de") == [])
        #expect(problems(try catalog(key, "ar", unit("التالي  (← or Space)")), "ar") == [])
        #expect(problems(try catalog(key, "ar", unit("التالي  (→ or Space)")), "ar").count >= 1)
    }

    @Test func arrowsSwapInRightToLeftOnly() throws {
        let key = "Next image (→)"
        #expect(problems(try catalog(key, "de", unit("Nächstes Bild (←)")), "de").count == 1)
        #expect(problems(try catalog(key, "de", unit("Nächstes Bild (→)")), "de") == [])
        #expect(problems(try catalog(key, "he", unit("התמונה הבאה (←)")), "he") == [])
        #expect(problems(try catalog("%@ → %@", "he", unit("%@ ← %@")), "he").count == 1)
        #expect(problems(try catalog("%@ → %@", "he", unit("%@ → %@")), "he") == [])
    }

    @Test func placeholdersInBracesStay() throws {
        let key = "Name: {name}_{n:3}"
        #expect(problems(try catalog(key, "de", unit("Name: {name}_{n:3}")), "de") == [])
        #expect(problems(try catalog(key, "de", unit("Name: {Name}_{n:3}")), "de").count == 1)
    }

    @Test func staleKeyIsReported() throws {
        let c = try catalog("Open…", "de", unit("Öffnen…"), entry: ["extractionState": "stale"])
        #expect(problems(c, "de").count == 1)
    }

    @Test func untranslatableKeyWithLettersIsReported() throws {
        #expect(problems(try catalog("JPEG", "de", nil, entry: ["shouldTranslate": false]), "de").count == 1)
        #expect(problems(try catalog("%", "de", nil, entry: ["shouldTranslate": false]), "de") == [])
    }

    @Test func percentSignBeforeAWordIsNotASpecifier() throws {
        let key = "% of the shorter side"
        #expect(problems(try catalog(key, "pl", unit("% krótszego boku")), "pl") == [])
        #expect(problems(try catalog(key, "ru", unit("% от более короткой стороны")), "ru") == [])
        #expect(problems(try catalog(key, "de", unit("% der kürzeren Seite")), "de") == [])
    }

    @Test func untranslatableKeyWithOnlySpecifiersIsAccepted() throws {
        for key in ["%lld × %lld · %@", "%lld / %lld", "%@ → %@", "%lld"] {
            #expect(problems(try catalog(key, "de", nil, entry: ["shouldTranslate": false]), "de") == [])
        }
    }

    @Test func tokenWithoutSubstitutionIsReported() throws {
        let files: [String: Any] = [
            "argNum": 1, "formatSpecifier": "lld",
            "variations": ["plural": ["one": unit("%arg file"), "other": unit("%arg files")]],
        ]
        var en = unit("%#@files@ done")
        en["substitutions"] = ["files": files]
        let missing = try catalog("%#@files@ done", en: en, "de", unit("%#@files@ fertig"))
        #expect(problems(missing, "de").count == 1)
        var de = unit("%#@files@ fertig")
        de["substitutions"] = ["files": [
            "argNum": 1, "formatSpecifier": "lld",
            "variations": ["plural": ["one": unit("%arg Datei"), "other": unit("%arg Dateien")]],
        ]]
        #expect(problems(try catalog("%#@files@ done", en: en, "de", de), "de") == [])
    }

    @Test func oneMayOmitCountOnlyWhereItMeansExactlyOne() throws {
        let en = plural(["one": "%lld file", "other": "%lld files"])
        // CLDR `one` also covers 21, 31 … in ru/uk.
        let ru = try catalog("%lld files", en: en, "ru", plural(["one": "один файл", "other": "%lld файлов"]))
        #expect(problems(ru, "ru").count == 1)
        let de = try catalog("%lld files", en: en, "de", plural(["one": "eine Datei", "other": "%lld Dateien"]))
        #expect(problems(de, "de") == [])
    }

    @Test func wholeStringPluralNeedsExactlyOneCount() throws {
        let en = plural(["one": "%lld of %lld file", "other": "%lld of %lld files"])
        let de = try catalog(
            "%lld of %lld files", en: en, "de", plural(["one": "eine von %lld Dateien", "other": "%lld von %lld Dateien"]))
        #expect(problems(de, "de").count == 2)
    }

    @Test func substitutionArgumentMustMatchTheSource() throws {
        func files(_ argNum: Int, _ specifier: String, _ one: String, _ other: String) -> [String: Any] {
            ["argNum": argNum, "formatSpecifier": specifier,
             "variations": ["plural": ["one": unit(one), "other": unit(other)]]]
        }
        var en = unit("%#@files@ done")
        en["substitutions"] = ["files": files(1, "lld", "%arg file", "%arg files")]
        var de = unit("%#@files@ fertig")
        de["substitutions"] = ["files": files(2, "@", "%arg Datei", "%arg Dateien")]
        #expect(problems(try catalog("%#@files@ done", en: en, "de", de), "de").count == 1)
    }

    @Test func variationsWithoutPluralHaveNoText() throws {
        #expect(problems(try catalog("Open…", "de", ["variations": [:]]), "de").count == 1)
        let device: [String: Any] = ["variations": ["device": ["mac": unit("", "new")]]]
        #expect(problems(try catalog("Open…", "de", device), "de").count == 1)
    }

    @Test func shippedCatalogHasNoProblemsInItsLanguages() throws {
        let catalog = try StringCatalog.load(StringCatalog.shippedURL)
        #expect(catalog.problems(languages: catalog.presentLanguages) == [])
    }

    @Test(.disabled("translations land in wave C; Task 11 enables this"))
    func shippedCatalogIsComplete() throws {
        let catalog = try StringCatalog.load(StringCatalog.shippedURL)
        #expect(catalog.problems(languages: StringCatalog.languages) == [])
    }

    @Test func infoPlistListsTheLanguages() throws {
        let url = StringCatalog.shippedURL.deletingLastPathComponent().appending(path: "Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let languages = (plist as? [String: Any])?["CFBundleLocalizations"] as? [String]
        #expect(languages == StringCatalog.languages)
    }
}
