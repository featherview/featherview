import SwiftUI

/// The full-screen slideshow's glass capsule (docs/DESIGN.md "Elements"): previous, play / pause, next, end.
/// The window's toolbar and menus do this while playing in the window, so it shows in full screen only.
struct SlideshowControls: View {
    let state: ViewerModel.SlideshowState
    let previous: () -> Void
    let togglePause: () -> Void
    let next: () -> Void
    let end: () -> Void

    var body: some View {
        HStack(spacing: Theme.slideshowControlsGap) {
            item("Previous", "chevron.backward", "Previous (←)", Theme.chevronGlyph, previous)
            if state == .playing {
                item("Pause", "pause.fill", "Pause (Space)", Theme.toolbarGlyph, togglePause)
            } else {
                item("Play", "play.fill", "Play (Space)", Theme.toolbarGlyph, togglePause)
            }
            item("Next", "chevron.forward", "Next (→)", Theme.chevronGlyph, next)
            item("End Slideshow", "xmark", "End slideshow (Esc)", Theme.toolbarGlyph, end)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.labelPrimary)
        .padding(Theme.slideshowControlsPadding)
        .glass(.card, cornerRadius: Theme.Radius.slideshowControls)
    }

    private func item(_ title: LocalizedStringKey, _ symbol: String, _ help: LocalizedStringKey, _ font: Font,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .frame(width: Theme.toolbarItem.width, height: Theme.toolbarItem.height)
                .contentShape(.rect)
        }
        .help(help)
        .accessibilityLabel(Text(title))
    }
}
