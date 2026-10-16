import FeatherviewCore
import SwiftUI

/// The folder chooser over the viewer; keys are handled by ViewerView. A click selects and opens too.
struct FolderChooserView: View {
    let model: ViewerModel

    var body: some View {
        if let chooser = model.chooser {
            VStack(alignment: .leading, spacing: 0) {
                Text(chooser.folder.lastPathComponent)
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(Array(chooser.entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Image(systemName: symbol(entry))
                        Text(label(entry))
                        Spacer()
                        if let count = model.chooserCounts[entry.url] {
                            Text(count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == chooser.selection ? Color.accentColor.opacity(0.35) : .clear,
                                in: .rect(cornerRadius: 4))
                    .contentShape(.rect)
                    .onTapGesture {
                        model.chooserMove(index - chooser.selection)
                        model.chooserOpen()
                    }
                }
                Text("→ open folder · ← up · Return show images · Esc cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding()
            .frame(width: 360)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
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
