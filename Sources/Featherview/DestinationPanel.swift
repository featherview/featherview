import FeatherviewCore
import SwiftUI

/// F7 / F8: the 14 destination slots over the viewer. Keys are handled by ViewerView.
struct DestinationPanel: View {
    @Bindable var model: ViewerModel
    let operation: FileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(operation == .move ? "Move to Folder" : "Copy to Folder")
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(0..<DestinationSlots.count, id: \.self) { slot in
                HStack {
                    Text(String(DestinationSlots.keys[slot]))
                        .monospaced()
                        .frame(width: 18)
                    Text(model.slots[slot]?.lastPathComponent ?? String(localized: "Empty"))
                        .foregroundStyle(model.slots[slot] == nil ? .secondary : .primary)
                        .help(model.slots[slot]?.path ?? "")
                    Spacer()
                    Button("Choose…") { model.chooseFolder(for: slot) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(slot == model.slots.lastUsed ? Color.accentColor.opacity(0.35) : .clear,
                            in: .rect(cornerRadius: 4))
            }
            Text("Press a key to pick a folder · Return uses the highlighted one · Esc cancels")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding()
        .frame(width: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}
