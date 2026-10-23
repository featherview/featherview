import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

/// One table of other spellings of a format's extension, for listing files and for the batch's own format.
@Suite struct ExtensionAliasTests {
    @Test func aliasesNameTheirFormat() {
        #expect(["jfif", "JIF", "jfi", "heif", "hif", "apng", "jpg", "Png"].map(ImageFormats.canonicalExtension)
                == ["jpg", "jpg", "jpg", "heic", "heic", "png", "jpg", "png"])
        // ImageIO reads these with a sibling format, but they aren't that format.
        #expect(ImageFormats.canonicalExtension("psb") == "psb")
        #expect(ImageFormats.canonicalExtension("pam") == "pam")
    }

    @Test func aliasesAndSiblingsAreListed() {
        for ext in ["jfif", "jif", "jfi", "heif", "hif", "apng", "psb", "pam"] {
            #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/tmp/a.\(ext)")), "\(ext)")
        }
    }

    /// Keep format: an alias saves in its format under its own name; a PSB is no PSD, so it isn't saved as one.
    @Test func batchKeepsEachInputsOwnFormat() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let jfif = dir.appendingPathComponent("a.jfif")
        try FileManager.default.copyItem(at: try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 40, height: 20), to: jfif)
        let heif = try Fixtures.writeImage(to: dir.appendingPathComponent("b.heif"), width: 40, height: 20, type: .heic)
        let apng = try Fixtures.writeAPNG(to: dir.appendingPathComponent("c.apng"), delays: [0.04, 0.04], width: 40, height: 20)
        let psb = try Fixtures.writeImage(to: dir.appendingPathComponent("d.psb"), width: 40, height: 20,
                                          type: UTType("com.adobe.photoshop-image")!)
        var settings = BatchSettings()
        settings.outputFolder = out.path
        settings.changeFormat = false
        settings.resize.isOn = true
        settings.resize.side = 10

        let results = await BatchConverter.run(BatchJob(inputs: [jfif, heif, apng, psb].map { BatchInput(url: $0) }, settings: settings))

        #expect(results.map(\.status) == [.converted, .converted, .converted, .failed])
        #expect(results.prefix(3).map { $0.output?.lastPathComponent } == ["a.jfif", "b.heif", "c.apng"])
        let types = try results.prefix(3).map { CGImageSourceCreateWithURL(try #require($0.output) as CFURL, nil).flatMap(CGImageSourceGetType) as String? }
        #expect(types == ["public.jpeg", "public.heif", "public.png"])
        #expect(results[3].message == "Can't save d.psb in its own format")
    }
}
