/// The viewer's single-character shortcuts. Arrows, ⌘⌫ and ⌦ are matched by the view itself.
public enum ViewerKey: Equatable, Sendable {
    case rotateRight, rotateLeft, toggleInfo, toggleFullScreen, fit, actualSize, zoomIn, zoomOut
    /// Commands that also have a ⌘ shortcut; the single key is for people switching over.
    case open, batch, minimize, settings, saveAs, about

    /// `shift` counts only for letters: some layouts need Shift to type the others
    /// ('+' is Shift+= on US keyboards, digits need Shift on AZERTY). Caps Lock is ignored.
    public static func action(characters: String, shift: Bool) -> ViewerKey? {
        let isLetter = characters.lowercased() != characters.uppercased()
        if shift, isLetter { return nil }
        switch characters.lowercased() {
        case "r": return .rotateRight
        case "l": return .rotateLeft
        case "i": return .toggleInfo
        case "f": return .toggleFullScreen
        case "0": return .fit
        case "1": return .actualSize
        case "+", "=": return .zoomIn
        case "-": return .zoomOut
        case "o": return .open
        case "b": return .batch
        case "m": return .minimize
        case "p": return .settings
        case "s": return .saveAs
        case "a": return .about
        default: return nil
        }
    }

    /// True when the arrow means next (or enter). Spec "Languages": in right-to-left languages
    /// ← and → follow the mirrored screen, so ← is next image and → is previous.
    public static func arrowGoesForward(isRightArrow: Bool, rightToLeft: Bool) -> Bool {
        isRightArrow != rightToLeft
    }
}
