import Foundation
import Testing

/// Rules the app target (no unit tests of its own) must keep, read from its source.
struct SourceRulesTests {
    static func lines(_ path: String) throws -> [String] {
        try String(contentsOf: Fixtures.repo.appending(path: path), encoding: .utf8).components(separatedBy: "\n")
    }

    @Test func everyNonisolatedUnsafeSaysWhyItIsSound() throws {
        let sources = Fixtures.repo.appending(path: "Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("nonisolated(unsafe)") {
                let reasoned = line.contains("//") || (index > 0 && lines[index - 1].trimmingCharacters(in: .whitespaces).hasPrefix("//"))
                #expect(reasoned, "\(file.lastPathComponent):\(index + 1) has nonisolated(unsafe) without a reason")
            }
        }
    }

    /// The window retains the guard; a strong delegate would close a cycle if SwiftUI's delegate holds the window.
    @Test func closeGuardHoldsTheOriginalDelegateWeakly() throws {
        let declaration = try Self.lines("Sources/Featherview/Viewer/CloseGuard.swift").first { $0.contains(" original:") }
        #expect(declaration?.contains("weak var original") == true)
    }
}
