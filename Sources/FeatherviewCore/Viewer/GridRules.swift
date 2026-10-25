import Foundation

/// The thumbnail grid's cell sizes, decode sizes and cache budget.
public enum ThumbnailSize {
    /// The slider's range in points.
    public static let range: ClosedRange<Double> = 64...256
    public static let standard = 128.0

    /// The cell's pixels rounded up to 128, 256, 384 or 512, so a slider drag re-decodes only
    /// when it crosses a step.
    public static func decodeSide(points: Double, scale: Double) -> Int {
        let steps = (points * scale / 128).rounded(.up)
        return min(512, max(128, Int(steps) * 128))
    }

    /// How many cells fill a row and how wide they are.
    public struct Columns: Equatable, Sendable {
        public let count: Int
        public let cell: Double
        public init(count: Int, cell: Double) {
            self.count = count
            self.cell = cell
        }
    }

    /// The column count whose cells come nearest to `target`, widened to whole points that fill `width` (the room
    /// between the side margins); the count moves on while the cells leave `range`. Without a width yet: the target.
    public static func columns(width: Double, target: Double, gap: Double) -> Columns {
        guard width > 0 else { return Columns(count: 1, cell: target) }
        var count = max(1, Int(((width + gap) / (target + gap)).rounded()))
        while count > 1, cell(count, width: width, gap: gap) < range.lowerBound { count -= 1 }
        while cell(count, width: width, gap: gap) > range.upperBound { count += 1 }
        return Columns(count: count, cell: cell(count, width: width, gap: gap))
    }

    /// + / − and the pinch: one column fewer (larger) or more; nil when that leaves `range`.
    public static func stepped(width: Double, target: Double, gap: Double, larger: Bool) -> Double? {
        let count = columns(width: width, target: target, gap: gap).count + (larger ? -1 : 1)
        guard count >= 1 else { return nil }
        let next = cell(count, width: width, gap: gap)
        return range.contains(next) ? next : nil
    }

    /// Magnification that takes one column away or adds one.
    public static let pinchStep = 0.15

    private static func cell(_ count: Int, width: Double, gap: Double) -> Double {
        ((width - Double(count - 1) * gap) / Double(count)).rounded(.down)
    }

    /// Three screens of pixels at 4 bytes each, for the largest screen: cells together cover at
    /// most one screen, however many there are.
    public static func cacheBudget(screens: [PixelSize]) -> Int {
        3 * (screens.map { $0.width * $0.height }.max() ?? 0) * 4
    }
}

/// A pinch's magnification in whole column steps (positive: larger), the rest kept for the next event.
public struct PinchSteps: Sendable {
    private var sum = 0.0

    public init() {}

    public mutating func add(_ magnification: Double) -> Int {
        sum += magnification
        let steps = Int(sum / ThumbnailSize.pinchStep)
        sum -= Double(steps) * ThumbnailSize.pinchStep
        return steps
    }

    /// The fingers left the trackpad.
    public mutating func end() { sum = 0 }
}

/// Which cells to decode, in order.
public enum GridWindow {
    /// The visible indices in order, then as many again ahead in the scroll direction, nearest
    /// first, clipped to `0..<count`.
    public static func wanted(visible: Range<Int>, count: Int, forward: Bool) -> [Int] {
        let shown = visible.clamped(to: 0..<max(count, 0))
        let ahead = forward
            ? Array(shown.upperBound..<min(count, shown.upperBound + shown.count))
            : Array((max(0, shown.lowerBound - shown.count)..<shown.lowerBound).reversed())
        return Array(shown) + ahead
    }
}

/// Where the grid's selection goes when the list changes.
public enum GridSelection {
    /// The first survivor after the last removed file, else the last survivor before it; nil when
    /// none survive.
    public static func focusAfterRemoval(urls: [URL], removed: Set<URL>) -> URL? {
        let last = urls.lastIndex { removed.contains($0) } ?? -1
        return urls[(last + 1)...].first { !removed.contains($0) }
            ?? urls[..<max(last, 0)].last { !removed.contains($0) }
    }

    /// The selection's indices in `urls`; files no longer listed drop out.
    public static func indices(of selected: Set<URL>, in urls: [URL]) -> IndexSet {
        // A few files (the grid opens with one): comparing beats hashing every URL (~3 ms for 10,000).
        if selected.count <= 16 { return IndexSet(selected.compactMap { urls.firstIndex(of: $0) }) }
        return IndexSet(urls.indices.filter { selected.contains(urls[$0]) })
    }

    /// Right-click: a selected cell keeps the selection, any other becomes it, as in Finder.
    public static func contextClick(_ index: Int, selection: Set<Int>) -> Set<Int> {
        selection.contains(index) ? selection : [index]
    }

    /// A plain click inside a selection of several waits for the mouse to go up: a drag takes the whole selection.
    public static func defersClick(_ index: Int, selection: Set<Int>, shift: Bool, command: Bool) -> Bool {
        !shift && !command && selection.count > 1 && selection.contains(index)
    }

    /// A click on cell `index` (Decision 10): ⇧ selects from the anchor's cell to it, in place of the selection;
    /// ⌘ toggles it; plain selects only it. The anchor is a file, so it follows its cell when the list changes;
    /// ⇧ with no anchor listed is a plain click.
    public static func click(_ index: Int, in urls: [URL], selection: Set<Int>, anchor: URL?,
                             shift: Bool, command: Bool) -> (selection: Set<Int>, anchor: URL) {
        if shift, let anchor, let from = urls.firstIndex(of: anchor) {
            return (Set(min(from, index)...max(from, index)), anchor)
        }
        guard command, !shift else { return ([index], urls[index]) }
        var selection = selection
        if selection.remove(index) == nil { selection.insert(index) }
        return (selection, urls[index])
    }
}

/// The grid's keys. Arrows belong to the collection view, other ⌘ keys to the menus.
public enum GridKey: Equatable, Sendable {
    case view, leave, quickLook, trash, move, copy, batch, larger, smaller, first, last, toggle, refresh
    case passOn(ViewerKey)

    /// `characters` is AppKit's `charactersIgnoringModifiers`.
    public static func action(characters: String, modifiers: MenuKey.Modifiers) -> GridKey? {
        if characters == "\u{7F}" { return modifiers == .command ? .trash : nil }  // ⌘⌫; plain ⌫ nothing
        if modifiers.isEmpty {
            switch characters {
            case "\r", "\u{3}": return .view
            case "\u{1B}": return .leave
            case " ": return .quickLook
            case "\u{F728}": return .trash  // ⌦
            case "\u{F70A}": return .move  // F7
            case "\u{F70B}": return .copy  // F8
            case "\u{F708}": return .refresh  // F5
            case "\u{F729}": return .first  // Home
            case "\u{F72B}": return .last  // End
            default: break
            }
        }
        // Shift may be needed to type a character key, as in the viewer.
        guard modifiers.subtracting(.shift).isEmpty,
              let key = ViewerKey.action(characters: characters, shift: modifiers.contains(.shift))
        else { return nil }
        switch key {
        case .batch: return .batch
        case .zoomIn: return .larger
        case .zoomOut: return .smaller
        case .toggleThumbnails: return .toggle
        case .open, .settings, .about, .minimize, .toggleFullScreen, .slideshow, .playInWindow: return .passOn(key)
        default: return nil
        }
    }
}
