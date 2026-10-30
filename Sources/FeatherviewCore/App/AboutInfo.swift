import Darwin
import Foundation

/// What the About window's Copy button puts on the pasteboard, for bug reports.
public enum AboutInfo {
    public static let repository = URL(string: "https://github.com/featherview/featherview")!
    public static let website = URL(string: "https://featherview.mynetx.net")!
    public static let sponsor = URL(string: "https://github.com/sponsors/mynetx")!

    /// Fields of `.github/ISSUE_TEMPLATE/bug_report.yml` that the app fills in (issue forms take them from the query).
    public enum BugReportField: String, CaseIterable, Sendable {
        case version, macOS = "macos", mac, crash
    }

    /// GitHub turns away longer new-issue links.
    static let maxURLLength = 8000

    /// A new issue from the bug report form with version, macOS and Mac model filled in, and a crash summary when given
    /// (cut at a line end to keep the link short enough).
    public static func bugReportURL(version: String, build: String, macOS: String, model: String, crash: String? = nil) -> URL {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func item(_ field: BugReportField, _ value: String) -> String {
            "&\(field.rawValue)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved)!)"
        }
        var link = repository.absoluteString + "/issues/new?template=bug_report.yml"
            + item(.version, "\(version) (\(build))") + item(.macOS, macOS) + item(.mac, model)
        if let crash {
            var lines = crash.components(separatedBy: "\n")
            while !lines.isEmpty, (link + item(.crash, lines.joined(separator: "\n"))).count > maxURLLength { lines.removeLast() }
            if !lines.isEmpty { link += item(.crash, lines.joined(separator: "\n")) }
        }
        return URL(string: link)!
    }

    public static func reportText(version: String, build: String, macOS: String, model: String) -> String {
        "Featherview \(version) (\(build))\nmacOS \(macOS)\n\(model)"
    }

    /// The Mac's model identifier, e.g. "Mac14,6"; empty if sysctl fails.
    public static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
