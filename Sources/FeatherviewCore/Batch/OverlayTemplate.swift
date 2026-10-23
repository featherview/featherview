import Foundation

/// The full-screen overlay text: a template with `{name}`, `{folder}`, `{path}`, `{index}`, `{count}`,
/// `{size}`, `{date}`. Unknown placeholders stay as typed, so a typo is visible, not silently dropped.
public enum OverlayTemplate {
    public static let placeholders = ["name", "folder", "path", "index", "count", "size", "date"]

    /// `{size}` (the file's own pixels, not the screen-size decode) and `{date}`.
    public static func fileValues(size: CGSize?, modified: Date?) -> [String: String] {
        var values: [String: String] = [:]
        if let size { values["size"] = "\(Int(size.width)) × \(Int(size.height))" }
        if let modified { values["date"] = modified.formatted(date: .abbreviated, time: .shortened) }
        return values
    }

    /// `{path}`: the file's full path, the home folder written as `~`.
    public static func path(of url: URL, home: URL) -> String {
        let path = url.path(percentEncoded: false), home = home.path(percentEncoded: false)
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }

    public static func render(_ template: String, values: [String: String]) -> String {
        // One pass over the template, so a value such as a file named "{date}.jpg" is never replaced again.
        template.replacing(/\{(\w+)\}/) { match in
            let key = String(match.1)
            return placeholders.contains(key) ? values[key] ?? "" : String(match.0)
        }
    }
}
