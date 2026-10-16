import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RenamePatternTests {
    @Test func tokens() {
        #expect(RenamePattern("{name}_{n:3}").baseName(original: "IMG", index: 7) == "IMG_007")
        #expect(RenamePattern("x{n}").baseName(original: "a", index: 12) == "x12")
        #expect(RenamePattern("{n:2}").baseName(original: "a", index: 123) == "123")
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
}
