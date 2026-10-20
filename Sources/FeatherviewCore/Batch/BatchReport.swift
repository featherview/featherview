import Foundation

/// The batch window's done view: the run in one sentence, then each failure by file name.
public enum BatchReport {
    /// "47 of 48 images converted in 1 min, 12 sec. 210 MB in, 96 MB out. Saved to ~/Desktop/Out."
    /// `folder` empty: next to the originals.
    public static func summary(results: [BatchResult], seconds: Double, bytesIn: Int, bytesOut: Int, folder: String) -> String {
        let converted = results.filter { $0.status == .converted }.count
        let total = results.count
        let duration = Duration.seconds(seconds.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        let sizeIn = Int64(bytesIn).formatted(.byteCount(style: .file))
        let sizeOut = Int64(bytesOut).formatted(.byteCount(style: .file))
        let place = folder.isEmpty
            ? String(localized: "next to the originals", comment: "Batch done summary: where the files went, after \"Saved to\"")
            : (folder as NSString).abbreviatingWithTildeInPath
        return String(localized: "\(converted) of \(total) images converted in \(duration). \(sizeIn) in, \(sizeOut) out. Saved to \(place).",
                      comment: "Batch done summary: converted count, list count, run time, bytes read, bytes written, output folder")
    }

    /// Each failed file's log line ("Can't open IMG_0412.heic"), in list order.
    public static func failures(_ results: [BatchResult]) -> [String] {
        results.filter { $0.status == .failed }.map(\.logLine)
    }
}
