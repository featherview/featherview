import Darwin
import Foundation

/// What the About window's Copy button puts on the pasteboard, for bug reports.
public enum AboutInfo {
    public static let repository = URL(string: "https://github.com/mynetx/featherview")!

    /// Fields of `.github/ISSUE_TEMPLATE/bug_report.yml` that the app fills in (issue forms take them from the query).
    public enum BugReportField: String, CaseIterable, Sendable {
        case version, macOS = "macos", mac
    }

    /// A new issue from the bug report form with version, macOS and Mac model filled in.
    public static func bugReportURL(version: String, build: String, macOS: String, model: String) -> URL {
        let values: [BugReportField: String] = [.version: "\(version) (\(build))", .macOS: macOS, .mac: model]
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let query = BugReportField.allCases.map { "&\($0.rawValue)=\(values[$0]!.addingPercentEncoding(withAllowedCharacters: unreserved)!)" }
        return URL(string: repository.absoluteString + "/issues/new?template=bug_report.yml" + query.joined())!
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
