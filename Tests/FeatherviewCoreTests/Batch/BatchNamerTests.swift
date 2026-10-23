import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RenamePatternTests {
    @Test func nameAndPaddedCounterFillIn() {
        #expect(RenamePattern("{name}_{n:3}").baseName(original: "IMG", index: 7) == "IMG_007")
        #expect(RenamePattern("x{n}").baseName(original: "a", index: 12) == "x12")
        #expect(RenamePattern("{n:2}").baseName(original: "a", index: 123) == "123")
    }

    @Test func padWidthIsCapped() {
        // A typo like {n:200000000} must not build a huge string for every file.
        #expect(RenamePattern("{n:20}").baseName(original: "a", index: 1) == "0000000001")
        #expect(RenamePattern("{n:200000000}").baseName(original: "a", index: 1).count == 10)
    }

    @Test func cannotEscapeTheOutputFolder() {
        #expect(RenamePattern("a/b:c").baseName(original: "z", index: 1) == "a-b-c")
    }

    @Test func emptyTemplateKeepsOriginal() {
        #expect(RenamePattern("").baseName(original: "z", index: 1) == "z")
    }

    @Test func originalNameIsNeverTreatedAsATemplate() {
        #expect(RenamePattern("{name}").baseName(original: "my{n}", index: 5) == "my{n}")
    }

    @Test func dateIsISODay() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 23, minute: 59))!
        #expect(RenamePattern("{date}_{name}_{n:2}").baseName(original: "IMG", index: 4, date: date) == "2024-03-05_IMG_04")
    }

    @Test func nilDateIsEmpty() {
        #expect(RenamePattern("{name}_{date}").baseName(original: "IMG", index: 1, date: nil) == "IMG_")
    }

    @Test func dateInOriginalNameStaysLiteral() {
        #expect(RenamePattern("{name}").baseName(original: "a{date}", index: 1, date: .now) == "a{date}")
    }
}

@Suite struct BatchNamerTests {
    func settings(changeFormat: Bool = true, pattern: String = "{name}", out: String = "/out",
                  format: String = "jpg", safety: SafetySettings = SafetySettings()) -> BatchSettings {
        var s = BatchSettings()
        s.changeFormat = changeFormat
        s.renamePattern = pattern
        s.outputFolder = out
        s.formatID = format
        s.safety = safety
        return s
    }

    func input(_ path: String, root: String? = nil) -> BatchInput {
        BatchInput(url: URL(fileURLWithPath: path), root: root.map { URL(fileURLWithPath: $0) })
    }

    @Test func counterAdvancesOnlyOnNext() {
        let inputs = [input("/a/x.png"), input("/a/y.png"), input("/a/z.png")]
        var namer = BatchNamer(settings: settings(pattern: "p{n:3}"), inputs: inputs) { _ in false }
        // y failed: next is never called for it, so z gets the next number.
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "p001.jpg")
        #expect(namer.next(for: inputs[2], date: nil).lastPathComponent == "p002.jpg")
    }

    @Test func patternAppliesWhenChangingFormat() {
        let inputs = [input("/a/x.png")]
        var namer = BatchNamer(settings: settings(pattern: "p{n}"), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).path == "/out/p1.jpg")
        var plain = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        #expect(plain.next(for: inputs[0], date: nil).path == "/out/x.jpg")
        var empty = BatchNamer(settings: settings(pattern: ""), inputs: inputs) { _ in false }
        #expect(empty.next(for: inputs[0], date: nil).path == "/out/x.jpg")
    }

    @Test func emptyFolderIsNextToOriginal() {
        let inputs = [input("/a/x.png"), input("/b/c/y.jpg")]
        for changeFormat in [true, false] {
            var namer = BatchNamer(settings: settings(changeFormat: changeFormat, out: ""), inputs: inputs) { _ in false }
            // Keeping the format, the input itself has the name: never replaced.
            let name = changeFormat ? "x.jpg" : "x 2.png"
            #expect(namer.next(for: inputs[0], date: nil).path == "/a/\(name)")
            #expect(namer.folder(for: inputs[1]).path == "/b/c")
        }
    }

    @Test func keepFormatKeepsExtension() {
        let inputs = [input("/a/x.PNG"), input("/a/noext")]
        var namer = BatchNamer(settings: settings(changeFormat: false, pattern: "{name}-{n}"), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "x-1.PNG")
        #expect(namer.next(for: inputs[1], date: nil).lastPathComponent == "noext-2")
    }

    @Test func clashesAreCaseInsensitive() {
        let inputs = [input("/a/a.jpg"), input("/b/A.png")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "a.jpg")
        #expect(namer.next(for: inputs[1], date: nil).lastPathComponent == "A 2.jpg")
    }

    @Test(arguments: [("Straße.png", "STRASSE"), ("ς.png", "Σ"), ("ﬀ.png", "FF")])
    func clashesFoldCaseLikeAPFS(name: String, pattern: String) {
        // APFS treats ß/ss, ς/σ and ﬀ/ff as one name; an input must never be handed out (and replaced).
        let inputs = [input("/a/" + name), input("/a/x.png")]
        var namer = BatchNamer(settings: settings(changeFormat: false, pattern: pattern, out: "/a",
                                                  safety: SafetySettings(replaceExisting: true)), inputs: inputs) { _ in true }
        #expect(namer.next(for: inputs[1], date: nil).lastPathComponent == pattern + " 2.png")
    }

    @Test(arguments: [".", ".."]) func dotNamesFallBackToTheOriginal(pattern: String) {
        // "<out>/.." is the output folder's parent: with Replace existing the caller would trash it.
        let inputs = [input("/a/scan")]
        var namer = BatchNamer(settings: settings(changeFormat: false, pattern: pattern,
                                                  safety: SafetySettings(replaceExisting: true)), inputs: inputs) { _ in true }
        #expect(namer.next(for: inputs[0], date: nil).path == "/out/scan")
    }

    @Test func existingFileGetsSuffix() {
        let inputs = [input("/a/x.png")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { $0.lastPathComponent == "x.jpg" }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "x 2.jpg")
    }

    @Test(arguments: [false, true]) func neverReplacesAnInput(replace: Bool) {
        // b.png's output name would be a.jpg, which is a later input (A.JPG) in the same folder.
        let inputs = [input("/a/b.png"), input("/a/A.JPG")]
        var namer = BatchNamer(settings: settings(pattern: "a", out: "/a",
                                                  safety: SafetySettings(replaceExisting: replace)),
                               inputs: inputs) { $0.lastPathComponent.lowercased() == "a.jpg" }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "a 2.jpg")
    }

    @Test func replaceExistingReturnsTheExistingName() {
        let inputs = [input("/a/x.png"), input("/b/x.png")]
        var namer = BatchNamer(settings: settings(safety: SafetySettings(replaceExisting: true)), inputs: inputs) { _ in true }
        #expect(namer.next(for: inputs[0], date: nil).path == "/out/x.jpg")
        // A name given earlier in this run is never replaced.
        #expect(namer.next(for: inputs[1], date: nil).path == "/out/x 2.jpg")
    }

    @Test func folderPlaceholder() {
        let namer = BatchNamer(settings: settings(out: "/out/{folder}"), inputs: []) { _ in false }
        #expect(namer.folder(for: input("/photos/Holiday/x.jpg")).path == "/out/Holiday")
        #expect(namer.folder(for: input("/x.jpg")).path == "/out/-")
        // {folder} is a path placeholder only, never in the rename pattern.
        let inputs = [input("/photos/Holiday/x.jpg")]
        var renamer = BatchNamer(settings: settings(changeFormat: false, pattern: "{folder}"), inputs: inputs) { _ in false }
        #expect(renamer.next(for: inputs[0], date: nil).lastPathComponent == "{folder}.jpg")
    }

    @Test func folderExpandsTilde() {
        let namer = BatchNamer(settings: settings(out: "~/Desktop/Out"), inputs: []) { _ in false }
        #expect(namer.folder(for: input("/photos/x.jpg")).path == NSHomeDirectory() + "/Desktop/Out")
    }

    // macOS 14's URL(fileURLWithPath:) expands no tilde, and no macOS expands ~user there; the
    // folder used must match what hasAbsoluteOutputFolder accepts.
    @Test func folderExpandsTildeLikeTheStartCheck() {
        let s = settings(out: "~root/Out")
        #expect(s.hasAbsoluteOutputFolder)
        let namer = BatchNamer(settings: s, inputs: []) { _ in false }
        #expect(namer.folder(for: input("/photos/x.jpg")).path == ("~root/Out" as NSString).expandingTildeInPath)
    }

    @Test func recreateSubfoldersAddsRelativePath() {
        let namer = BatchNamer(settings: settings(safety: SafetySettings(recreateSubfolders: true)), inputs: []) { _ in false }
        #expect(namer.folder(for: input("/photos/2024/May/x.jpg", root: "/photos")).path == "/out/2024/May")
        #expect(namer.folder(for: input("/photos/x.jpg", root: "/photos")).path == "/out")
    }

    @Test func filesWithoutRootIgnoreRecreate() {
        let namer = BatchNamer(settings: settings(safety: SafetySettings(recreateSubfolders: true)), inputs: []) { _ in false }
        #expect(namer.folder(for: input("/photos/2024/x.jpg")).path == "/out")
    }

    @Test func longNamesAreTrimmedTo255Bytes() {
        let long = String(repeating: "a", count: 252)
        let inputs = [input("/a/\(long).png"), input("/b/\(long).png"), input("/c/x.png")]
        var namer = BatchNamer(settings: settings(format: "heic"), inputs: inputs) { _ in false }
        var renamer = BatchNamer(settings: settings(pattern: String(repeating: "\u{00E9}", count: 200)),
                                 inputs: inputs) { _ in false }
        let names = [namer.next(for: inputs[0], date: nil), namer.next(for: inputs[1], date: nil),
                     renamer.next(for: inputs[2], date: nil)].map(\.lastPathComponent)
        #expect(names.allSatisfy { $0.decomposedStringWithCanonicalMapping.utf8.count <= 255 })
        #expect(names[0].hasSuffix(".heic") && names[1].hasSuffix(" 2.heic") && names[2].hasSuffix(".jpg"))
    }

    @Test(.timeLimit(.minutes(1))) func hugeExtensionDoesNotHang() {
        // A legal 255-byte name whose extension alone leaves no room for a " 2" suffix.
        let inputs = [input("/a/x." + String(repeating: "e", count: 253))]
        var namer = BatchNamer(settings: settings(changeFormat: false, out: ""), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent.hasPrefix(" 2."))
    }

    @Test func symlinkedInputsTargetIsNeverReplaced() throws {
        let dir = try Fixtures.makeTempDir()
        let real = dir.appendingPathComponent("b", isDirectory: true), links = dir.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
        let target = try Fixtures.writeImage(to: real.appendingPathComponent("photo.jpg"), width: 8, height: 8)
        let link = links.appendingPathComponent("photo.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let inputs = [input(link.path)]
        var namer = BatchNamer(settings: settings(out: real.path, safety: SafetySettings(replaceExisting: true)), inputs: inputs)
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "photo 2.jpg")
    }
}

// Several outputs per input (frames, pages, tiles).
extension BatchNamerTests {
    func names(_ namer: inout BatchNamer, _ input: BatchInput, _ parts: [String]) -> [String] {
        namer.names(for: input, date: nil, parts: parts).map(\.lastPathComponent)
    }

    @Test func partsAppendedWhenPatternLacksPart() {
        let inputs = [input("/a/a.gif")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        #expect(names(&namer, inputs[0], ["01", "02"]) == ["a-01.jpg", "a-02.jpg"])
    }

    @Test func explicitPartPlaceholder() {
        let inputs = [input("/a/a.gif")]
        var namer = BatchNamer(settings: settings(pattern: "{part}_{name}"), inputs: inputs) { _ in false }
        #expect(names(&namer, inputs[0], ["01", "02"]) == ["01_a.jpg", "02_a.jpg"])
    }

    @Test func singleOutputHasNoSuffix() {
        let inputs = [input("/a/a.gif")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        #expect(names(&namer, inputs[0], []) == ["a.jpg"])
        var explicit = BatchNamer(settings: settings(pattern: "{name}_{part}"), inputs: inputs) { _ in false }
        #expect(names(&explicit, inputs[0], []) == ["a_1.jpg"])
    }

    @Test func counterCountsInputs() {
        let inputs = [input("/a/a.gif"), input("/a/b.png")]
        var namer = BatchNamer(settings: settings(pattern: "{n}"), inputs: inputs) { _ in false }
        #expect(names(&namer, inputs[0], ["01", "02"]) == ["1-01.jpg", "1-02.jpg"])
        #expect(names(&namer, inputs[1], []) == ["2.jpg"])
    }

    @Test(arguments: [false, true]) func partsClashGetSuffixes(replace: Bool) {
        let one = [input("/a/a.gif")]
        var namer = BatchNamer(settings: settings(), inputs: one) { $0.lastPathComponent == "a-01.jpg" }
        #expect(names(&namer, one[0], ["01", "02"]) == ["a-01 2.jpg", "a-02.jpg"])
        // Names given earlier in this run are never handed out again, even with Replace existing.
        let two = [input("/a/a.gif"), input("/b/a.tif")]
        var run = BatchNamer(settings: settings(safety: SafetySettings(replaceExisting: replace)), inputs: two) { _ in false }
        #expect(names(&run, two[0], ["01", "02"]) == ["a-01.jpg", "a-02.jpg"])
        #expect(names(&run, two[1], ["01", "02"]) == ["a-01 2.jpg", "a-02 2.jpg"])
    }

    @Test func longNamesKeepTheirPartLabel() {
        let long = String(repeating: "x", count: 252)
        let inputs = [input("/a/\(long).gif"), input("/b/\(long).png")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        let parts = names(&namer, inputs[0], ["01", "02", "03"])
        let base = String(repeating: "x", count: 255 - "-01.jpg".utf8.count)
        #expect(parts == ["01", "02", "03"].map { base + "-\($0).jpg" })
        // A single output with the same long name doesn't clash with part 1.
        #expect(names(&namer, inputs[1], []) == [String(repeating: "x", count: 251) + ".jpg"])
    }

    @Test func staticFolderMatchesInstance() {
        var s = settings()
        s.outputFolder = "/out/{folder}"
        s.safety = SafetySettings(recreateSubfolders: true)
        let namer = BatchNamer(settings: s, inputs: []) { _ in false }
        for i in [input("/photos/Holiday/x.jpg"),
                  BatchInput(url: URL(fileURLWithPath: "/photos/2024/May/x.jpg"), root: URL(fileURLWithPath: "/photos"))] {
            #expect(BatchNamer.folder(for: i, settings: s) == namer.folder(for: i))
        }
    }
}

@Suite struct BatchCopyTests {
    @Test func copyKeepsBytes() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("in.jpg"), width: 8, height: 8)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let result = try BatchCopy.copy(source, to: out.appendingPathComponent("renamed.jpg"))
        #expect(result.lastPathComponent == "renamed.jpg")
        #expect(try Data(contentsOf: result) == Data(contentsOf: source))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path) == ["renamed.jpg"])  // no temp left
    }

    @Test func copyNeverReplaces() throws {
        let dir = try Fixtures.makeTempDir()
        let source = try Fixtures.writeImage(to: dir.appendingPathComponent("in.jpg"), width: 8, height: 8)
        let taken = dir.appendingPathComponent("taken.jpg")
        try Data("keep me".utf8).write(to: taken)
        let result = try BatchCopy.copy(source, to: taken)
        #expect(result.lastPathComponent == "taken 2.jpg")
        #expect(try Data(contentsOf: taken) == Data("keep me".utf8))
        #expect(try Data(contentsOf: result) == Data(contentsOf: source))
    }
}
