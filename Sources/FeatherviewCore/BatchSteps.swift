import Foundation

/// The batch window's steps column (spec "Window"): output, rename, the operations in spec order, safety.
public enum BatchStep: String, CaseIterable, Identifiable, Sendable {
    case output, rename, crop, resize, orientation, colour, filters, canvas, border, text, watermark, safety

    public var id: String { rawValue }

    public static let operations: [BatchStep] = [.crop, .resize, .orientation, .colour, .filters, .canvas, .border, .text, .watermark]

    /// False when the mode skips this step (shown dimmed).
    public func isUsed(in s: BatchSettings) -> Bool {
        switch self {
        case .rename: s.mode != .convert
        case _ where Self.operations.contains(self): s.mode != .rename
        default: true
        }
    }

    public func isOn(in s: BatchSettings) -> Bool {
        switch self {
        case .output: true
        case .rename: s.mode != .convert
        case .crop: s.crop.isOn
        case .resize: s.resize.isOn
        case .orientation: s.orientation.isOn
        case .colour: s.colour.isOn
        case .filters: s.filters.isOn
        case .canvas: s.canvas.isOn
        case .border: s.border.isOn
        case .text: s.text.isOn
        case .watermark: s.watermark.isOn
        case .safety: s.safety != SafetySettings()  // every flag is off by default
        }
    }

    /// "HEIC", "2048", "on", "" (off or unused).
    public func summary(in s: BatchSettings) -> String {
        guard isUsed(in: s) else { return "" }
        switch self {
        case .output:
            return s.mode == .rename ? String(localized: "Same format") : s.format.name
        case .rename:
            return s.renamePattern
        case .resize:
            let r = s.resize
            guard r.isOn else { return "" }
            switch r.mode {
            case .longestSide, .shortestSide: return "\(r.side)"
            case .widthHeight:
                return String(localized: "\(r.width.map(String.init) ?? "–") × \(r.height.map(String.init) ?? "–")")
            case .megapixels: return String(localized: "\(r.megapixels.formatted()) MP")
            case .percent: return String(localized: "\(r.percentWidth.formatted()) %")
            }
        default:
            return isOn(in: s) ? String(localized: "on") : ""
        }
    }
}

/// An input row's state during and after a run.
public enum BatchRowState: Equatable, Sendable {
    case waiting, working
    case done(String)
    case failed(String)
}

/// The batch window's run view: when Start is allowed, time left, each row's state.
public enum BatchProgress {
    public static func canStart(isRunning: Bool, scans: Int, inputCount: Int, settings: BatchSettings) -> Bool {
        // A scan still in flight would append files the run never sees.
        !isRunning && scans == 0 && inputCount > 0 && (settings.mode == .rename || settings.hasAbsoluteOutputFolder)
    }

    /// Estimated seconds left once 3 files are done, from the time spent not paused.
    public static func secondsLeft(elapsed: Double, paused: Double, done: Int, total: Int) -> Double? {
        guard done >= 3, done < total else { return nil }
        return (elapsed - paused) / Double(done) * Double(total - done)
    }

    /// `index` is the row's place in the list, `committed` how many results are in.
    public static func rowState(result: BatchResult?, index: Int?, isRunning: Bool, isPaused: Bool,
                                committed: Int, workers: Int = BatchConverter.defaultWorkers) -> BatchRowState? {
        if let result {
            switch result.status {
            case .converted: return .done(result.output?.lastPathComponent ?? "")
            case .failed: return .failed(result.logLine)
            case .notStarted: return nil
            }
        }
        guard isRunning else { return nil }
        // shortcut: the converter doesn't report starts; files run in list order, so the next
        // `workers` uncommitted rows are shown working. Exact once the converter reports starts.
        guard let index else { return .waiting }
        return !isPaused && index < committed + workers ? .working : .waiting
    }
}
