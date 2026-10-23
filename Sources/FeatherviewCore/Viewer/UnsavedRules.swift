/// A way out of the picture a window shows.
public enum ViewerCommand: CaseIterable, Sendable {
    case next, previous, first, last, open, close, newFromClipboard, quit
}

/// What a picture from the clipboard, not saved yet, lets through: every way out of it asks first (Save…, Don't
/// Save, Cancel), because leaving drops it.
public enum UnsavedRules {
    public static func asksFirst(_ command: ViewerCommand, hasUnsaved: Bool) -> Bool {
        switch command {
        case .next, .previous, .first, .last, .open, .close, .newFromClipboard, .quit: hasUnsaved
        }
    }
}
