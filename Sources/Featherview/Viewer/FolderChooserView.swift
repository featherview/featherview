import FeatherviewCore
import SwiftUI

/// The folder chooser over the viewer; keys are handled by ViewerView. A click selects and opens too.
/// A 400 pt glass sheet (docs/DESIGN.md "Elements").
struct FolderChooserView: View {
    let model: ViewerModel
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let chooser = model.chooser {
            VStack(alignment: .leading, spacing: Theme.panelGap) {
                HStack(spacing: Theme.rowGap) {
                    Image(systemName: "folder")
                        .font(Theme.rowGlyph)
                        .foregroundStyle(Theme.labelSecondary)
                    Text(verbatim: chooser.folder.lastPathComponent)
                        .font(Theme.panelTitle)
                        .foregroundStyle(Theme.labelTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("end of folder")
                        .font(Theme.hint)
                        .foregroundStyle(Theme.labelTertiary)
                }
                .frame(height: Theme.sheetHeaderHeight)
                if chooser.entries.count <= 8 {
                    VStack(spacing: 0) { rows(chooser) }
                } else {
                    // Long lists (1,000 subfolders) scroll, built lazily, keeping the selection in view.
                    ScrollViewReader { proxy in
                        ScrollView { LazyVStack(spacing: 0) { rows(chooser) } }
                            .frame(maxHeight: Theme.chooserListHeight)
                            .onChange(of: chooser.selection, initial: true) { proxy.scrollTo(chooser.selection) }
                    }
                }
                footer
            }
            .padding(Theme.panelPadding)
            .frame(width: Theme.chooserWidth)
            .glass(.sheet, cornerRadius: Theme.Radius.panel)
        }
    }

    private func rows(_ chooser: FolderChooser) -> some View {
        ForEach(Array(chooser.entries.enumerated()), id: \.offset) { index, entry in
            let selected = index == chooser.selection
            HStack(spacing: Theme.rowGap) {
                Image(systemName: symbol(entry))
                    .font(Theme.rowGlyph)
                    .foregroundStyle(selected ? Theme.onAccent : Theme.labelSecondary)
                Text(label(entry))
                    .font(selected ? Theme.rowSelected : Theme.row)
                    .foregroundStyle(selected ? Theme.onAccent : Theme.labelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count = model.chooserCounts[entry.url] {
                    Text(count, format: .number)
                        .font(Theme.rowValue)
                        .foregroundStyle(selected ? Theme.onAccentSecondary : Theme.labelSecondary)
                }
            }
            .padding(.horizontal, Theme.rowPadding)
            .frame(height: Theme.chooserRowHeight)
            .background(selected ? Theme.accent : .clear, in: .rect(cornerRadius: Theme.Radius.chooserRow))
            .contentShape(.rect)
            .onTapGesture {
                model.chooserMove(index - chooser.selection)
                model.chooserOpen()
            }
        }
    }

    /// The keys and what they do; the arrows swap in right-to-left layouts, as the keys do (ViewerView).
    private var footer: some View {
        let rtl = layoutDirection == .rightToLeft
        return HStack(spacing: Theme.footerGap) {
            hint(rtl ? "←" : "→", "open folder")
            FooterSeparator()
            hint(rtl ? "→" : "←", "up")
            FooterSeparator()
            hint("↩", "show images")
            FooterSeparator()
            hint("esc", "cancel")
        }
        .font(Theme.hint)
        .foregroundStyle(Theme.labelTertiary)
        .lineLimit(1)
    }

    private func hint(_ key: String, _ verb: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.keyCapGap) {
            KeyCap(key: key, size: .footer)
            Text(verb)
        }
    }

    private func label(_ entry: FolderChooser.Entry) -> String {
        switch entry {
        case .again: String(localized: "This folder again")
        case .parent(let url): url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        case .subfolder(let url): url.lastPathComponent
        }
    }

    private func symbol(_ entry: FolderChooser.Entry) -> String {
        switch entry {
        case .again: "arrow.counterclockwise"
        case .parent: "arrow.up"
        case .subfolder: "folder"
        }
    }
}

/// The 1 × 10 line between footer hints.
struct FooterSeparator: View {
    var body: some View {
        Theme.separator.frame(width: 1, height: Theme.footerSeparatorHeight)
    }
}

extension AnyTransition {
    /// Sheets: in 160 ms (scale 0.97 → 1 with a fade), out 120 ms in reverse; none under Reduce Motion.
    static func sheet(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let change = AnyTransition.scale(scale: Theme.Motion.sheetScale).combined(with: .opacity)
        return .asymmetric(insertion: change.animation(.easeOut(duration: Theme.Motion.sheetIn)),
                           removal: change.animation(.easeIn(duration: Theme.Motion.sheetOut)))
    }
}
