import Foundation

/// Featherview's own crash reports in the user's DiagnosticReports folder, offered for a bug report (never sent by the app).
public enum CrashReports {
    public static let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
    /// The app's process name; the extensions' reports carry their own (FeatherviewThumbnail, FeatherviewPreview).
    static let processName = "Featherview"
    static let maxFrames = 15

    /// The newest readable report of the app's own process modified after `newerThan`.
    public static func newest(in folder: URL = folder, newerThan: Date?) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = files.compactMap { url -> (URL, Date)? in
            // macOS names a report after its process; the header decides, the name only skips other apps' files unread.
            guard url.pathExtension == "ips", url.lastPathComponent.hasPrefix(processName),
                  let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  newerThan.map({ date > $0 }) ?? true else { return nil }
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.first { url, _ in
            guard let data = try? Data(contentsOf: url), isOwn(data) else { return false }
            return summary(of: data) != nil
        }?.0
    }

    /// The exception type and the crashed thread's first 15 frames as "image  symbol" lines; nil if the report can't be read.
    public static func summary(of report: Data) -> String? {
        guard let (_, body) = split(report),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let exception = json["exception"] as? [String: Any], let type = exception["type"] as? String,
              let faulting = json["faultingThread"] as? Int, let threads = json["threads"] as? [[String: Any]],
              threads.indices.contains(faulting), let frames = threads[faulting]["frames"] as? [[String: Any]] else { return nil }
        let images = (json["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        let lines = frames.prefix(maxFrames).map { frame in
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
            let symbol = frame["symbol"] as? String ?? (frame["imageOffset"] as? Int).map { "+0x" + String($0, radix: 16) } ?? "?"
            return "\(image)  \(symbol)"
        }
        let signal = (exception["signal"] as? String).map { " (\($0))" } ?? ""
        return ([type + signal] + lines).joined(separator: "\n")
    }

    /// The header line names the process: the app's own, not an extension's or another app's.
    static func isOwn(_ report: Data) -> Bool {
        guard let (header, _) = split(report),
              let json = try? JSONSerialization.jsonObject(with: header) as? [String: Any] else { return false }
        return (json["app_name"] as? String ?? json["name"] as? String) == processName
    }

    private static func split(_ report: Data) -> (header: Data, body: Data)? {
        guard let newline = report.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        return (report[..<newline], report[(newline + 1)...])
    }
}
