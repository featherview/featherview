/// The viewer's single-character shortcuts. Arrows and ⌘⌫ are matched by the view itself.
public enum ViewerKey: Equatable, Sendable {
    case rotateRight, rotateLeft, toggleInfo, toggleFullScreen, fit, actualSize, zoomIn, zoomOut

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
        default: return nil
        }
    }
}
