import Foundation

/// The batch window's live output names (spec "Output"), named as the converter names them.
public enum BatchPreviewNames {
    public struct Result: Sendable {
        public var names: [String] = []
        /// How many names follow the shown ones.
        public var more = 0
        public var folder = ""
        /// Frames or pages per file counted so far, to pass to the next call.
        public var frameCounts: [URL: Int] = [:]
        /// The task was cancelled: only `frameCounts` holds.
        public var cancelled = false
    }

    /// The first five names (each input's parts in order) as if every file succeeds, how many names
    /// follow, and the first file's folder.
    public static func compute(_ s: BatchSettings, inputs: [BatchInput], frameCounts: [URL: Int] = [:]) -> Result {
        var result = Result(frameCounts: frameCounts)
        guard let first = inputs.first else { return result }
        var namer = BatchNamer(settings: s, inputs: inputs)
        let usesDate = s.renamePattern.contains("{date}")
        var total = 0
        for input in inputs {
            // A large folder takes seconds: stop for a newer job.
            guard !Task.isCancelled else { result.cancelled = true; return result }
            var frames = 1
            if s.frames.isOn {
                frames = result.frameCounts[input.url] ?? Self.frames(of: input.url)
                result.frameCounts[input.url] = frames
            }
            total += parts(s, frames: frames)
            guard result.names.count < 5 else { continue }
            let date = usesDate ? Self.date(s, url: input.url) : nil
            let urls = namer.names(for: input, date: date, parts: labels(s, frames: frames, limit: 5 - result.names.count))
            result.names += urls.prefix(5 - result.names.count).map(\.lastPathComponent)
        }
        result.more = total - result.names.count
        result.folder = namer.folder(for: first).path
        return result
    }

    /// As the converter counts them: an animation's frames, else a document's pages.
    public static func frames(of url: URL) -> Int {
        Animation.read(url)?.frameCount ?? ImageDecoder.pageCount(of: url)
    }

    /// `{date}` as the converter fills it: the Date Taken step's new date, else the file's own.
    public static func date(_ s: BatchSettings, url: URL) -> Date? {
        s.dateTaken.newDate(for: url).flatMap(MetadataReader.exifDate) ?? MetadataReader.dateTaken(of: url)
    }

    /// How many outputs one input gives, as `PartLabels.combined` counts them (at least one).
    public static func parts(_ s: BatchSettings, frames: Int) -> Int {
        let tiles = s.tiles.isOn ? TileStep.clamped(s.tiles.rows) * TileStep.clamped(s.tiles.columns) : 1
        return max(frames, 1) * tiles
    }

    static func labels(_ s: BatchSettings, frames: Int, limit: Int) -> [String] {
        PartLabels.combined(frames: frames, rows: s.tiles.isOn ? s.tiles.rows : 1, columns: s.tiles.isOn ? s.tiles.columns : 1,
                            limit: limit)
    }
}
