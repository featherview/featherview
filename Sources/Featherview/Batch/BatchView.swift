import FeatherviewCore
import SwiftUI

/// The batch window (design "Layout"): images leading; the cards over the preview trailing, with Presets
/// and the main button under them; while running, the run view in place of cards and preview.
struct BatchView: View {
    @Bindable var model: BatchModel
    @State private var namingPreset = false
    @State private var presetName = ""
    @State private var confirmingReplace = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationSplitView {
            BatchImagesColumn(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            VStack(spacing: 0) {
                if model.isFinished && !model.isRunning {
                    BatchSummaryBar(model: model)
                    Divider()
                }
                if model.isRunning {
                    BatchRunView(model: model)
                        .frame(maxHeight: .infinity)
                } else {
                    // The cards give way first: the preview keeps its height and the cards scroll.
                    BatchCards(model: model)
                        .layoutPriority(-1)
                    Divider()
                    BatchPreview(model: model)
                        .frame(minHeight: Theme.batchPreviewMinHeight, maxHeight: Theme.batchPreviewHeight)
                }
                Divider()
                bottomBar
            }
            .background { cardKeys }
        }
        .navigationTitle("Batch Convert")
        .frame(minWidth: 960, minHeight: 600)
        .sheet(isPresented: $namingPreset) { presetSheet }
        .confirmationDialog("Delete the preset \(model.loadedPreset ?? "")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deletePreset() }
        } message: {
            Text("Its settings are lost.")
        }
        .alert(model.notice ?? "", isPresented: Binding { model.notice != nil } set: { if !$0 { model.notice = nil } }) {
            Button("OK") { model.notice = nil }
        }
    }

    /// ⌘2, ⌘3, ⌘4 open Format, Size and Name, matching their numbers.
    private var cardKeys: some View {
        ZStack {
            ForEach(BatchCard.core) { card in
                if let number = card.number {
                    Button(card.title) { model.openCard = card }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                }
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(model.isRunning)
    }

    private var bottomBar: some View {
        HStack {
            presetsMenu
            Spacer()
            if model.isRunning {
                if model.isPaused {
                    Button("Resume") { model.resume() }
                } else {
                    Button("Pause") { model.pause() }
                }
                Button("Stop") { model.stop() }
            } else {
                // ⌘↩, not Return: Return in a field only confirms the value, it must not start a long batch.
                Button("Convert \(model.inputs.items.count) Images") { model.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, Theme.rowPadding)
        .padding(.vertical, Theme.messagePadding)
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(model.presetNames, id: \.self) { name in
                Toggle(name, isOn: Binding { model.loadedPreset == name } set: { _ in model.loadPreset(name) })
            }
            if !model.presetNames.isEmpty { Divider() }
            Button("Save Preset…") {
                presetName = model.loadedPreset ?? ""
                namingPreset = true
            }
            Button("Delete Preset…") { confirmingDelete = true }
                .disabled(model.loadedPreset == nil)
        } label: {
            if let name = model.loadedPreset {
                Text(model.presetName == nil ? String(localized: "\(name) (edited)", comment: "Preset menu: a preset with unsaved changes") : name)
            } else {
                Text("Presets")
            }
        }
        .fixedSize()
        .disabled(model.isRunning)
    }

    private var presetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Preset").font(.headline)
            TextField("Name", text: $presetName)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { namingPreset = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if model.replacesAnotherPreset(presetName) { return confirmingReplace = true }
                    model.savePreset(presetName)
                    namingPreset = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .confirmationDialog("Replace the preset \(presetName.trimmingCharacters(in: .whitespacesAndNewlines))?",
                            isPresented: $confirmingReplace) {
            Button("Replace", role: .destructive) {
                model.savePreset(presetName)
                namingPreset = false
            }
        } message: {
            Text("Its settings are lost.")
        }
    }
}
