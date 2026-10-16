/// The full-screen overlay text: a template with `{name}`, `{folder}`, `{index}`, `{count}`,
/// `{size}`, `{date}`. Unknown placeholders stay as typed, so a typo is visible, not silently dropped.
public enum OverlayTemplate {
    public static let placeholders = ["name", "folder", "index", "count", "size", "date"]

    public static func render(_ template: String, values: [String: String]) -> String {
        var result = template
        for key in placeholders {
            result = result.replacingOccurrences(of: "{\(key)}", with: values[key] ?? "")
        }
        return result
    }
}
