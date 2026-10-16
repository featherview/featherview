import Foundation

/// Output file names for batch conversion.
/// `{name}` = original base name, `{n}` = 1-based counter, `{n:3}` = counter zero-padded to 3 digits (at most 10).
/// Any other text is kept as typed.
public struct RenamePattern: Equatable, Sendable {
    public let template: String

    public init(_ template: String) {
        self.template = template
    }

    /// Base name without extension. "/" and ":" are replaced so a name can't leave the output folder.
    public func baseName(original: String, index: Int) -> String {
        // Counter first: an original name that happens to contain "{n}" must stay literal.
        let numbered = template.replacing(/\{n(?::(\d+))?\}/) { match in
            let digits = String(index)
            let width = min(match.1.flatMap { Int($0) } ?? 0, 10)  // a typo like {n:99999999} must not build a huge name
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        let name = numbered
            .replacingOccurrences(of: "{name}", with: original)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return name.isEmpty ? original : name
    }
}
