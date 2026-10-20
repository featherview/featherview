import Foundation

/// The batch window's done view: the run in one sentence, then each failure by file name.
public enum BatchReport {
    /// "47 of 48 images converted in 1 minute, 12 seconds. 210 MB in, 96 MB out. Saved to ~/Desktop/Out."
    /// `folder` empty: next to the originals.
    public static func summary(results: [BatchResult], seconds: Double, bytesIn: Int, bytesOut: Int, folder: String) -> String {
        let converted = results.filter { $0.status == .converted }.count
        let total = results.count
        let duration = duration(seconds)
        let sizeIn = Int64(bytesIn).formatted(.byteCount(style: .file))
        let sizeOut = Int64(bytesOut).formatted(.byteCount(style: .file))
        guard !folder.isEmpty else {
            return String(localized: "\(converted) of \(total) images converted in \(duration). \(sizeIn) in, \(sizeOut) out. Saved next to the originals.",
                          comment: "Batch done summary: converted count, list count, run time, bytes read, bytes written")
        }
        let place = (folder as NSString).abbreviatingWithTildeInPath
        return String(localized: "\(converted) of \(total) images converted in \(duration). \(sizeIn) in, \(sizeOut) out. Saved to \(place).",
                      comment: "Batch done summary: converted count, list count, run time, bytes read, bytes written, output folder")
    }

    /// The folder Show in Finder opens: the typed output folder when it exists and has no `{folder}`
    /// (which becomes each input's folder name), else the first converted output's folder; nil when neither exists.
    public static func folderToShow(setting: String, results: [BatchResult]) -> URL? {
        let typed = (setting as NSString).expandingTildeInPath
        var isFolder: ObjCBool = false
        if typed.hasPrefix("/"), !typed.contains("{folder}"),
           FileManager.default.fileExists(atPath: typed, isDirectory: &isFolder), isFolder.boolValue {
            return URL(fileURLWithPath: typed, isDirectory: true)
        }
        return results.first { $0.status == .converted }?.output?.deletingLastPathComponent()
    }

    /// The run time in words ("1 hour, 2 minutes, 6 seconds"). Wide, since abbreviations can end in a
    /// period ("6 Sek.") and the sentence adds its own.
    static func duration(_ seconds: Double, locale: Locale = .current) -> String {
        Duration.seconds(seconds.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    /// Each failed file's log line ("Can't open IMG_0412.heic"), in list order.
    public static func failures(_ results: [BatchResult]) -> [String] {
        results.filter { $0.status == .failed }.map(\.logLine)
    }
}
