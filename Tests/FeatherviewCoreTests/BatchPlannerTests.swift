import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RenamePatternTests {
    @Test func tokens() {
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
}

@Suite struct BatchPlannerTests {
    let out = URL(fileURLWithPath: "/out")

    @Test func clashesGetNumberedSuffixes() {
        let inputs = ["/a/x.png", "/b/x.png", "/c/y.png"].map { URL(fileURLWithPath: $0) }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .jpeg)
        let plan = BatchPlanner.outputURLs(for: job) { $0.lastPathComponent == "y.jpg" }
        #expect(plan.map(\.lastPathComponent) == ["x.jpg", "x 2.jpg", "y 2.jpg"])
    }

    @Test func neverOverwritesAnInput() {
        let input = URL(fileURLWithPath: "/a/p.jpg")
        let job = BatchJob(inputs: [input], outputFolder: URL(fileURLWithPath: "/a"), format: .jpeg)
        #expect(BatchPlanner.outputURLs(for: job) { _ in false }.first?.lastPathComponent == "p 2.jpg")
    }

    @Test func namesDifferingOnlyInCaseClash() {
        let inputs = ["/a/A.png", "/b/a.png"].map { URL(fileURLWithPath: $0) }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .png)
        #expect(BatchPlanner.outputURLs(for: job) { _ in false }.map(\.lastPathComponent) == ["A.png", "a 2.png"])
    }

    @Test func namesFitTheFileNameLimit() {
        // APFS allows 255 bytes per name; a longer extension or a clash suffix must not exceed it.
        let long = String(repeating: "a", count: 252)
        let heic = BatchJob(inputs: [URL(fileURLWithPath: "/a/\(long).png")], outputFolder: out, format: .heic)
        let pngs = BatchJob(inputs: ["/a", "/b"].map { URL(fileURLWithPath: "\($0)/\(long).png") },
                            outputFolder: out, format: .png)
        let multibyte = BatchJob(inputs: [URL(fileURLWithPath: "/a/x.png")], outputFolder: out, format: .jpeg,
                                 rename: RenamePattern(String(repeating: "\u{00E9}", count: 200)))
        let names = (BatchPlanner.outputURLs(for: heic) { _ in false }
            + BatchPlanner.outputURLs(for: pngs) { _ in false }
            + BatchPlanner.outputURLs(for: multibyte) { _ in false }).map(\.lastPathComponent)
        #expect(names.allSatisfy { $0.decomposedStringWithCanonicalMapping.utf8.count <= 255 })
        #expect(names[0].hasSuffix(".heic") && names[2].hasSuffix(" 2.png") && names[1] != names[2])
        #expect(names[3].hasSuffix(".jpg"))
    }

    @Test func manyClashesPlanInLinearTime() {
        // Quadratic probing took over a minute for 2000 clashing names.
        let inputs = (0..<3000).map { URL(fileURLWithPath: "/src/\($0)/IMG.jpg") }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .jpeg, rename: RenamePattern("holiday"))
        let start = Date()
        let plan = BatchPlanner.outputURLs(for: job) { _ in false }
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(Set(plan.map { $0.path.lowercased() }).count == 3000)
        #expect(plan[2999].lastPathComponent == "holiday 3000.jpg")
    }

    @Test func suffixedNameFromAnotherInputStillClashes() {
        let inputs = ["/a/x.png", "/b/x 2.png", "/c/x.png"].map { URL(fileURLWithPath: $0) }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .jpeg)
        let plan = BatchPlanner.outputURLs(for: job) { _ in false }
        #expect(plan.map(\.lastPathComponent) == ["x.jpg", "x 2.jpg", "x 3.jpg"])
    }

    @Test func danglingSymlinkCountsAsTaken() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("x.jpg").path,
                                                   withDestinationPath: "/nonexistent/target.jpg")
        let job = BatchJob(inputs: [URL(fileURLWithPath: "/a/x.png")], outputFolder: dir, format: .jpeg)
        #expect(BatchPlanner.outputURLs(for: job).first?.lastPathComponent == "x 2.jpg")
    }
}
