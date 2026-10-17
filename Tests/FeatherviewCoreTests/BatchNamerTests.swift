import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RenamePatternDateTests {
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
    func settings(_ mode: BatchMode = .convert, pattern: String = "{name}", out: String = "/out",
                  format: String = "jpg", safety: SafetySettings = SafetySettings()) -> BatchSettings {
        var s = BatchSettings()
        s.mode = mode
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
        var namer = BatchNamer(settings: settings(.convertAndRename, pattern: "p{n:3}"), inputs: inputs) { _ in false }
        // y failed: next is never called for it, so z gets the next number.
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "p001.jpg")
        #expect(namer.next(for: inputs[2], date: nil).lastPathComponent == "p002.jpg")
    }

    @Test func convertModeKeepsNames() {
        let inputs = [input("/a/x.png")]
        var namer = BatchNamer(settings: settings(.convert, pattern: "p{n}"), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).path == "/out/x.jpg")
        var empty = BatchNamer(settings: settings(.convertAndRename, pattern: ""), inputs: inputs) { _ in false }
        #expect(empty.next(for: inputs[0], date: nil).path == "/out/x.jpg")
    }

    @Test func renameModeKeepsExtension() {
        let inputs = [input("/a/x.PNG"), input("/a/noext")]
        var namer = BatchNamer(settings: settings(.rename, pattern: "{name}-{n}"), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "x-1.PNG")
        #expect(namer.next(for: inputs[1], date: nil).lastPathComponent == "noext-2")
    }

    @Test func clashesAreCaseInsensitive() {
        let inputs = [input("/a/a.jpg"), input("/b/A.png")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "a.jpg")
        #expect(namer.next(for: inputs[1], date: nil).lastPathComponent == "A 2.jpg")
    }

    @Test func existingFileGetsSuffix() {
        let inputs = [input("/a/x.png")]
        var namer = BatchNamer(settings: settings(), inputs: inputs) { $0.lastPathComponent == "x.jpg" }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent == "x 2.jpg")
    }

    @Test(arguments: [false, true]) func neverReplacesAnInput(replace: Bool) {
        // b.png's output name would be a.jpg, which is a later input (A.JPG) in the same folder.
        let inputs = [input("/a/b.png"), input("/a/A.JPG")]
        var namer = BatchNamer(settings: settings(.convertAndRename, pattern: "a", out: "/a",
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
        var renamer = BatchNamer(settings: settings(.rename, pattern: "{folder}"), inputs: inputs) { _ in false }
        #expect(renamer.next(for: inputs[0], date: nil).lastPathComponent == "{folder}.jpg")
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
        var renamer = BatchNamer(settings: settings(.convertAndRename, pattern: String(repeating: "\u{00E9}", count: 200)),
                                 inputs: inputs) { _ in false }
        let names = [namer.next(for: inputs[0], date: nil), namer.next(for: inputs[1], date: nil),
                     renamer.next(for: inputs[2], date: nil)].map(\.lastPathComponent)
        #expect(names.allSatisfy { $0.decomposedStringWithCanonicalMapping.utf8.count <= 255 })
        #expect(names[0].hasSuffix(".heic") && names[1].hasSuffix(" 2.heic") && names[2].hasSuffix(".jpg"))
    }

    @Test(.timeLimit(.minutes(1))) func hugeExtensionDoesNotHang() {
        // A legal 255-byte name whose extension alone leaves no room for a " 2" suffix.
        let inputs = [input("/a/x." + String(repeating: "e", count: 253))]
        var namer = BatchNamer(settings: settings(.rename, out: ""), inputs: inputs) { _ in false }
        #expect(namer.next(for: inputs[0], date: nil).lastPathComponent.hasPrefix(" 2."))
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
