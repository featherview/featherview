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

    /// + / − : ×1.25 or ÷1.25 within `range`.
    public static func stepped(_ points: Double, larger: Bool) -> Double {
        let next = larger ? points * 1.25 : points / 1.25
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// Three screens of pixels at 4 bytes each, for the largest screen: cells together cover at
    /// most one screen, however many there are.
    public static func cacheBudget(screens: [PixelSize]) -> Int {
        3 * (screens.map { $0.width * $0.height }.max() ?? 0) * 4
    }
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
