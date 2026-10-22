import Foundation

/// The batch window's cards: Format, Size and Name always shown (numbered after the images, step 1),
/// the rarer steps added on demand.
public enum BatchCard: String, CaseIterable, Identifiable, Sendable {
    case format, size, name, frames, crop, orientation, colour, filters, canvas, border, text, watermark, tiles, dateTaken

    public var id: String { rawValue }

    public static let core: [BatchCard] = [.format, .size, .name]
    /// The Add Step menu's order.
    public static let extras: [BatchCard] = [.frames, .crop, .orientation, .colour, .filters, .canvas, .border, .text, .watermark,
                                             .tiles, .dateTaken]
    /// Spec "Per-image operations": Size runs where Resize does.
    private static let processingOrder: [BatchCard] = [.frames, .crop, .size, .orientation, .colour, .filters, .canvas, .border,
                                                       .text, .watermark, .tiles, .dateTaken]

    /// The card's place in the user's order (the images are 1); nil for added steps.
    public var number: Int? {
        switch self {
        case .format: 2
        case .size: 3
        case .name: 4
        default: nil
        }
    }

    /// Core cards always; an extra while its step is on.
    public func isAdded(in s: BatchSettings) -> Bool {
        switch self {
        case .format, .size, .name: true
        case .crop: s.crop.isOn
        case .orientation: s.orientation.isOn
        case .colour: s.colour.isOn
        case .filters: s.filters.isOn
        case .canvas: s.canvas.isOn
        case .border: s.border.isOn
        case .text: s.text.isOn
        case .watermark: s.watermark.isOn
        case .frames: s.frames.isOn
        case .tiles: s.tiles.isOn
        case .dateTaken: s.dateTaken.isOn
        }
    }

    /// Turns an extra's step on or off; core cards stay.
    public func setAdded(_ on: Bool, in s: inout BatchSettings) {
        switch self {
        case .format, .size, .name: break
        case .crop: s.crop.isOn = on
        case .orientation: s.orientation.isOn = on
        case .colour: s.colour.isOn = on
        case .filters: s.filters.isOn = on
        case .canvas: s.canvas.isOn = on
        case .border: s.border.isOn = on
        case .text: s.text.isOn = on
        case .watermark: s.watermark.isOn = on
        case .frames: s.frames.isOn = on
        case .tiles: s.tiles.isOn = on
        case .dateTaken: s.dateTaken.isOn = on
        }
    }

    /// Whether the card's step is applied in this batch (Size: when Change size is on).
    private func isApplied(in s: BatchSettings) -> Bool {
        self == .size ? s.resize.isOn : number == nil && isAdded(in: s)
    }

    /// The folded card's line, in words: "JPEG · 85", "Longest side 2048", "trip-{n:3} · Out", "Brightness +10".
    public func summary(in s: BatchSettings) -> String {
        let on = String(localized: "On", comment: "Batch card summary: the step is on, nothing more specific to say")
        switch self {
        case .format:
            guard s.changeFormat else {
                return s.copiesUnchanged
                    ? String(localized: "Keep format · copied unchanged", comment: "Batch Format card: files keep their format and are copied byte for byte")
                    : String(localized: "Keep format · saved again", comment: "Batch Format card: files keep their format and are saved again")
            }
            let format = s.format
            // The encoder searches a quality that reaches the target size and ignores the quality setting.
            if format.optionFields.contains(.targetSize), let kb = s.options.targetSizeKB, kb > 0 {
                return String(localized: "\(format.name) · \(String(kb)) KB", comment: "Batch Format card: format name and its target file size")
            }
            let usesQuality = format.optionFields.contains(.quality)
                && !(format.optionFields.contains(.lossless) && s.options.lossless)
            guard usesQuality else { return format.name }
            return String(localized: "\(format.name) · \(s.options.quality)", comment: "Batch Format card: format name and its quality")
        case .size:
            let r = s.resize
            guard r.isOn else { return String(localized: "Original size", comment: "Batch Size card: sizes unchanged") }
            switch r.mode {
            // Pixel counts without grouping ("2048"), like width × height.
            case .longestSide: return String(localized: "Longest side \(String(r.side))", comment: "Batch Size card: pixels")
            case .shortestSide: return String(localized: "Shortest side \(String(r.side))", comment: "Batch Size card: pixels")
            case .widthHeight:
                return String(localized: "\(r.width.map(String.init) ?? "–") × \(r.height.map(String.init) ?? "–")")
            case .megapixels: return String(localized: "\(r.megapixels.formatted()) MP")
            case .percent:
                let w = (r.percentWidth / 100).formatted(.percent)
                guard !r.keepAspect, r.percentHeight != r.percentWidth else { return w }
                return String(localized: "\(w) × \((r.percentHeight / 100).formatted(.percent))")
            }
        case .name:
            let place = s.outputFolder.isEmpty
                ? String(localized: "Next to the originals", comment: "Batch Name card: where files are saved")
                : ((s.outputFolder as NSString).expandingTildeInPath as NSString).lastPathComponent
            return String(localized: "\(s.renamePattern) · \(place)", comment: "Batch Name card: rename pattern and the folder saved to")
        case .crop:
            let c = s.crop
            return c.width > 0 && c.height > 0 ? String(localized: "\(String(c.width)) × \(String(c.height))") : on
        case .orientation:
            let o = s.orientation
            var parts: [String] = []
            if o.rotate == .left { parts.append(String(localized: "Rotate left", comment: "Batch Rotate and Flip card summary")) }
            if o.rotate == .right { parts.append(String(localized: "Rotate right", comment: "Batch Rotate and Flip card summary")) }
            if o.flipHorizontal { parts.append(String(localized: "Flip horizontally", comment: "Batch Rotate and Flip card summary")) }
            if o.flipVertical { parts.append(String(localized: "Flip vertically", comment: "Batch Rotate and Flip card summary")) }
            return Self.list(parts) ?? on
        case .colour:
            let c = s.colour
            var parts: [String] = []
            if c.greyscale { parts.append(String(localized: "Greyscale", comment: "Batch Colour card summary")) }
            if c.negative { parts.append(String(localized: "Negative", comment: "Batch Colour card summary")) }
            if c.autoAdjust { parts.append(String(localized: "Auto colours", comment: "Batch Colour card summary")) }
            if c.brightness != 0 { parts.append(String(localized: "Brightness \(Self.signed(c.brightness))", comment: "Batch Colour card summary")) }
            if c.contrast != 0 { parts.append(String(localized: "Contrast \(Self.signed(c.contrast))", comment: "Batch Colour card summary")) }
            if c.saturation != 0 { parts.append(String(localized: "Saturation \(Self.signed(c.saturation))", comment: "Batch Colour card summary")) }
            if c.gamma != 1 { parts.append(String(localized: "Gamma \(c.gamma.formatted())", comment: "Batch Colour card summary")) }
            if c.sharpen != 0 { parts.append(String(localized: "Sharpen \(c.sharpen)", comment: "Batch Colour card summary")) }
            if c.blur != 0 { parts.append(String(localized: "Blur \(c.blur)", comment: "Batch Colour card summary")) }
            if let n = c.reduceColours { parts.append(String(localized: "\(n) colours", comment: "Batch Colour card summary: reduce colour depth")) }
            return Self.list(parts) ?? on
        case .filters:
            let f = s.filters
            var parts: [String] = []
            if f.unsharpMask != 0 { parts.append(String(localized: "Unsharp mask \(f.unsharpMask)", comment: "Batch Filters card summary")) }
            if f.noiseReduction != 0 { parts.append(String(localized: "Noise reduction \(f.noiseReduction)", comment: "Batch Filters card summary")) }
            if f.sepia != 0 { parts.append(String(localized: "Sepia \(f.sepia)", comment: "Batch Filters card summary")) }
            if f.colourTemperature > 0 { parts.append(String(localized: "Warmer \(f.colourTemperature)", comment: "Batch Filters card summary")) }
            if f.colourTemperature < 0 { parts.append(String(localized: "Cooler \(-f.colourTemperature)", comment: "Batch Filters card summary")) }
            if f.autoLevels { parts.append(String(localized: "Auto levels", comment: "Batch Filters card summary")) }
            return Self.list(parts) ?? on
        case .canvas:
            let c = s.canvas
            switch c.method {
            case .totalSize: return String(localized: "\(String(c.width)) × \(String(c.height))")
            case .aspectRatio: return String(localized: "\(c.ratioWidth.formatted()):\(c.ratioHeight.formatted())", comment: "Batch Canvas card summary: aspect ratio")
            case .perSide:
                return c.autoCropBorders ? String(localized: "Auto-crop borders", comment: "Batch Canvas card summary") : on
            }
        case .border:
            let b = s.border
            return b.innerWidth > 0
                ? String(localized: "\(b.outerWidth) px and \(b.innerWidth) px", comment: "Batch Border card summary: outer and inner border widths")
                : String(localized: "\(b.outerWidth) px", comment: "Batch Border card summary: border width")
        case .text:
            let line = s.text.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return line.isEmpty ? on : line
        case .watermark:
            let w = s.watermark
            return String(localized: "\(Self.anchorName(w.position)) · \(w.opacity.formatted(.percent))",
                          comment: "Batch Watermark card summary: position and opacity")
        case .frames:
            return String(localized: "Every frame or page", comment: "Batch Frames and Pages card summary")
        case .tiles:
            let t = s.tiles
            return t.overlap == 0
                ? String(localized: "\(String(t.columns)) × \(String(t.rows))", comment: "Batch Tiles card summary: columns × rows")
                : String(localized: "\(String(t.columns)) × \(String(t.rows)), overlap \(t.overlap) px",
                         comment: "Batch Tiles card summary: columns × rows and the pixels neighbouring tiles share")
        case .dateTaken:
            let d = s.dateTaken
            switch d.mode {
            case .set:
                guard let date = Self.wallTime(d.setTo) else {
                    return String(localized: "Choose a date", comment: "Batch Date Taken card summary: no date set yet")
                }
                var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
                style.timeZone = .gmt
                return String(localized: "Set to \(date.formatted(style))", comment: "Batch Date Taken card summary: the date and time set")
            case .shift:
                guard d.shiftSeconds != 0 else {
                    return String(localized: "No shift", comment: "Batch Date Taken card summary: shift by zero")
                }
                let duration = Duration.seconds(d.shiftSeconds == .min ? .max : abs(d.shiftSeconds))  // abs(Int.min) traps
                    .formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated))
                return d.shiftSeconds > 0
                    ? String(localized: "Later by \(duration)", comment: "Batch Date Taken card summary: shifted later, e.g. 1 hr, 30 min")
                    : String(localized: "Earlier by \(duration)", comment: "Batch Date Taken card summary: shifted earlier, e.g. 1 hr, 30 min")
            }
        }
    }

    /// "Applied: crop → size → watermark": the steps that are on, in processing order; nil when none is.
    public static func appliedLine(_ s: BatchSettings) -> String? {
        let steps = processingOrder.filter { $0.isApplied(in: s) }
        guard !steps.isEmpty else { return nil }
        let names = steps.map(\.stepName).joined(separator: " → ")
        return String(localized: "Applied: \(names)", comment: "Batch preview: the steps applied, in processing order, joined by arrows")
    }

    /// The step's name inside the applied line (lower case in English).
    private var stepName: String {
        switch self {
        case .format: String(localized: "format", comment: "Batch applied line: step name")
        case .size: String(localized: "size", comment: "Batch applied line: step name")
        case .name: String(localized: "name", comment: "Batch applied line: step name")
        case .crop: String(localized: "crop", comment: "Batch applied line: step name")
        case .orientation: String(localized: "rotate and flip", comment: "Batch applied line: step name")
        case .colour: String(localized: "colour", comment: "Batch applied line: step name")
        case .filters: String(localized: "filters", comment: "Batch applied line: step name")
        case .canvas: String(localized: "canvas", comment: "Batch applied line: step name")
        case .border: String(localized: "border", comment: "Batch applied line: step name")
        case .text: String(localized: "text", comment: "Batch applied line: step name")
        case .watermark: String(localized: "watermark", comment: "Batch applied line: step name")
        case .frames: String(localized: "frames and pages", comment: "Batch applied line: step name")
        case .tiles: String(localized: "tiles", comment: "Batch applied line: step name")
        case .dateTaken: String(localized: "date taken", comment: "Batch applied line: step name")
        }
    }

    /// An EXIF wall time "yyyy:MM:dd HH:mm:ss" as a date in GMT (formatted back in GMT, it reads the same).
    private static func wallTime(_ exif: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: exif)
    }

    private static func signed(_ n: Int) -> String { n.formatted(.number.sign(strategy: .always())) }

    private static func list(_ parts: [String]) -> String? {
        parts.isEmpty ? nil : parts.formatted(.list(type: .and, width: .narrow))
    }

    private static func anchorName(_ a: ImageAnchor) -> String {
        switch a {
        case .topLeft: String(localized: "Top left", comment: "A position in the image")
        case .top: String(localized: "Top", comment: "A position in the image")
        case .topRight: String(localized: "Top right", comment: "A position in the image")
        case .left: String(localized: "Left", comment: "A position in the image")
        case .center: String(localized: "Centre", comment: "A position in the image")
        case .right: String(localized: "Right", comment: "A position in the image")
        case .bottomLeft: String(localized: "Bottom left", comment: "A position in the image")
        case .bottom: String(localized: "Bottom", comment: "A position in the image")
        case .bottomRight: String(localized: "Bottom right", comment: "A position in the image")
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
        // An empty folder means next to each original.
        !isRunning && scans == 0 && inputCount > 0 && (settings.outputFolder.isEmpty || settings.hasAbsoluteOutputFolder)
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
