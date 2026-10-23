import Foundation
import ImageIO
import Testing

struct DocumentIconTests {
    /// Images Preview and Quick Look also read keep the system's JPEG and PNG icons.
    static let systemIconTypes: Set = ["net.mynetx.featherview.jfif", "net.mynetx.featherview.apng"]

    @Test func ownTypesHaveTheFeatherDocumentIcon() throws {
        let info = try #require(try QuickLookSupportTests.plist("Resources/Info.plist"))
        let declarations = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        for declaration in declarations {
            let id = try #require(declaration["UTTypeIdentifier"] as? String)
            if Self.systemIconTypes.contains(id) {
                #expect(declaration["UTTypeIcons"] == nil, "\(id)")
                continue
            }
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            let firstExtension = try #require((tags?["public.filename-extension"] as? [String])?.first, "\(id)")
            let icons = declaration["UTTypeIcons"] as? [String: String]
            #expect(icons?["UTTypeIconBadgeName"] == "DocumentBadge", "\(id)")
            #expect(icons?["UTTypeIconText"] == firstExtension.uppercased(), "\(id)")
        }
        #expect(declarations.count > Self.systemIconTypes.count)
    }

    @Test func documentBadgeIsAnIconsetInTheAssetCatalog() throws {
        let dir = Fixtures.repo.appending(path: "Resources/Assets.xcassets/DocumentBadge.iconset")
        var expected: [String: Int] = [:]
        for size in [16, 32, 128, 256, 512] {
            expected["icon_\(size)x\(size).png"] = size
            expected["icon_\(size)x\(size)@2x.png"] = size * 2
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(Set(names) == Set(expected.keys))
        for (name, pixels) in expected where names.contains(name) {
            let source = try #require(CGImageSourceCreateWithURL(dir.appending(path: name) as CFURL, nil))
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            #expect(props?[kCGImagePropertyPixelWidth] as? Int == pixels, "\(name)")
        }
    }
}
