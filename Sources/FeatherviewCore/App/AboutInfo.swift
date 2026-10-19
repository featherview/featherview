import Darwin

/// What the About window's Copy button puts on the pasteboard, for bug reports.
public enum AboutInfo {
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
