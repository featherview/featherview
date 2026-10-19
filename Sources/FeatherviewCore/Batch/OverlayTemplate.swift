import Foundation

/// The full-screen overlay text: a template with `{name}`, `{folder}`, `{index}`, `{count}`,
/// `{size}`, `{date}`. Unknown placeholders stay as typed, so a typo is visible, not silently dropped.
public enum OverlayTemplate {
    public static let placeholders = ["name", "folder", "index", "count", "size", "date"]

    /// `{size}` (the file's own pixels, not the screen-size decode) and `{date}`. Reads the file: call it off the main thread.
    public static func fileValues(of url: URL) -> [String: String] {
        var values: [String: String] = [:]
        if let size = ImageDecoder.displaySize(of: url) { values["size"] = "\(Int(size.width)) × \(Int(size.height))" }
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            values["date"] = date.formatted(date: .abbreviated, time: .shortened)
        }
        return values
    }

    public static func render(_ template: String, values: [String: String]) -> String {
        // One pass over the template, so a value such as a file named "{date}.jpg" is never replaced again.
        template.replacing(/\{(\w+)\}/) { match in
            let key = String(match.1)
            return placeholders.contains(key) ? values[key] ?? "" : String(match.0)
        }
    }
}
