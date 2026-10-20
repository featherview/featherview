import Foundation
import Testing

/// Finder shows these names as a file's Kind, so they are translated like the app's own text.
@Suite struct InfoPlistStringsTests {
    @Test func everyKindNameIsTranslated() throws {
        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: Fixtures.repo.appending(path: "Resources/Info.plist")), format: nil) as? [String: Any])
        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let types = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let names = Set(documents.compactMap { $0["CFBundleTypeName"] as? String }
            + types.compactMap { $0["UTTypeDescription"] as? String })
        let catalog = try StringCatalog.load(Fixtures.repo.appending(path: "Resources/InfoPlist.xcstrings"))
        #expect(names.subtracting(catalog.strings.keys).sorted() == [])
        #expect(catalog.problems(languages: StringCatalog.languages) == [])
    }

    /// One document type per own format, so Finder names each one instead of a catch-all.
    @Test func ownFormatsHaveOneDocumentTypeEach() throws {
        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: Fixtures.repo.appending(path: "Resources/Info.plist")), format: nil) as? [String: Any])
        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        for document in documents {
            #expect((document["LSItemContentTypes"] as? [String])?.count == 1, "\(document["CFBundleTypeName"] ?? "")")
        }
    }
}
