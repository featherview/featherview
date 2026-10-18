import SwiftUI

/// A key as text in a cap (docs/DESIGN.md "Key caps"): ⌘O, →, ↩, esc. Never an icon font.
struct KeyCap: View {
    enum Size {
        /// The empty window's caps: 11 Medium, padding 3 × 7, radius 5.
        case regular
        /// Footer hints: padding 1 × 5, radius 4.
        case footer
    }

    let key: String
    var size = Size.regular

    var body: some View {
        let radius = size == .regular ? Theme.Radius.keyCap : Theme.Radius.small
        Text(verbatim: key)
            .font(Theme.keyCap)
            .foregroundStyle(Theme.keyCapText)
            .padding(size == .regular ? Theme.keyCapPadding : Theme.footerKeyCapPadding)
            .background(Theme.keyCapFill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.keyCapLine, lineWidth: 1))
    }
}
