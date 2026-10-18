import FeatherviewCore
import SwiftUI

/// F7 / F8: the 14 destination slots over the viewer, a 480 pt glass sheet (docs/DESIGN.md "Elements").
/// Keys are handled by ViewerView.
struct DestinationPanel: View {
    @Bindable var model: ViewerModel
    let operation: FileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelGap) {
            HStack {
                Text(operation == .move ? "Move to Folder" : "Copy to Folder")
                    .font(Theme.panelTitle)
                    .foregroundStyle(Theme.labelTitle)
                Spacer(minLength: 0)
                Text(verbatim: operation == .move ? "F7" : "F8")
                    .font(Theme.hint)
                    .foregroundStyle(Theme.labelTertiary)
            }
            .frame(height: Theme.sheetHeaderHeight)
            VStack(spacing: 0) {
                ForEach(0..<DestinationSlots.count, id: \.self) { slot in row(slot) }
            }
            HStack(spacing: Theme.footerGap) {
                Text("Press a key to pick a folder")
                FooterSeparator()
                HStack(spacing: Theme.keyCapGap) {
                    KeyCap(key: "↩", size: .footer)
                    Text("uses the highlighted one")
                }
                FooterSeparator()
                HStack(spacing: Theme.keyCapGap) {
                    KeyCap(key: "esc", size: .footer)
                    Text("cancels")
                }
            }
            .font(Theme.hint)
            .foregroundStyle(Theme.labelTertiary)
            .lineLimit(1)
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.moveSheetWidth)
        .glass(.sheet, cornerRadius: Theme.Radius.panel)
    }

    private func row(_ slot: Int) -> some View {
        let selected = slot == model.slots.lastUsed
        let folder = model.slots[slot]
        return HStack(spacing: Theme.rowGap) {
            Text(String(DestinationSlots.keys[slot]))
                .font(Theme.slotKey)
                .foregroundStyle(selected ? Color.white : Theme.keyCapText)
                .frame(width: Theme.slotKeySize, height: Theme.slotKeySize)
                .background(selected ? Theme.onAccentKeyFill : Theme.keyCapFill, in: .rect(cornerRadius: Theme.Radius.slotKey))
                .overlay {
                    if !selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.slotKey).strokeBorder(Theme.keyCapLine, lineWidth: 1)
                    }
                }
            Text(folder?.lastPathComponent ?? String(localized: "Empty"))
                .font(selected ? Theme.rowSelected : Theme.row)
                .foregroundStyle(selected ? Color.white : folder == nil ? Theme.labelTertiary : Theme.labelPrimary)
                .lineLimit(1)
                .help(folder?.path ?? "")
            Spacer(minLength: 0)
            Button { model.chooseFolder(for: slot) } label: {
                Text("Choose…")
                    .font(Theme.smallButton)
                    .foregroundStyle(selected ? Color.white : Theme.labelPrimary)
                    .padding(.horizontal, Theme.smallButtonPadding)
                    .frame(height: Theme.smallButtonHeight)
                    .background(selected ? Theme.onAccentButtonFill : Theme.keyCapFill, in: .rect(cornerRadius: Theme.Radius.slotKey))
                    .overlay {
                        if !selected {
                            RoundedRectangle(cornerRadius: Theme.Radius.slotKey).strokeBorder(Theme.badgeLine, lineWidth: 1)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Theme.moveRowLeading)
        .padding(.trailing, Theme.moveRowTrailing)
        .frame(height: Theme.moveRowHeight)
        .background(selected ? Theme.accent : .clear, in: .rect(cornerRadius: Theme.Radius.moveRow))
    }
}
