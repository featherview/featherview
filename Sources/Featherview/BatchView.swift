import FeatherviewCore
import SwiftUI

/// The batch window (spec "Window"): images, steps, the selected step's settings; while running,
/// the run view in place of the last two.
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
                } else {
                    HStack(spacing: 0) {
                        BatchStepsColumn(model: model)
                            .frame(width: 230)
                        Divider()
                        VStack(spacing: 0) {
                            BatchStepDetail(step: model.step, model: model)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            BatchPreview(model: model)
                        }
                    }
                }
            }
        }
        .toolbar { toolbar }
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Groups, so macOS 26 draws each as a capsule; 14 and 15 look as before.
        ToolbarItemGroup(placement: .principal) {
            Picker("Mode", selection: $model.settings.mode) {
                Text("Convert").tag(BatchMode.convert)
                Text("Rename").tag(BatchMode.rename)
                Text("Convert and Rename").tag(BatchMode.convertAndRename)
            }
            // A menu, not segments: three segments with "Convert and Rename" push Start into the overflow
            // menu at the window's default width, and there the segments lose their names.
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(model.isRunning)
        }
        ToolbarItemGroup {
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
            .disabled(model.isRunning)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isRunning {
                if model.isPaused {
                    Button("Resume") { model.resume() }
                } else {
                    Button("Pause") { model.pause() }
                }
                Button("Stop") { model.stop() }
            } else {
                // ⌘↩, not Return: Return in a field only confirms the value, it must not start a long batch.
                Button("Start") { model.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canStart)
            }
        }
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

/// Output, Operations, Files; each row the step's title and summary, dimmed when the mode doesn't use it.
private struct BatchStepsColumn: View {
    @Bindable var model: BatchModel

    var body: some View {
        List(selection: Binding<BatchStep?> { model.step } set: { if let step = $0 { model.step = step } }) {
            Section("Output") { rows([.output, .rename]) }
            Section("Operations") { rows(BatchStep.operations) }
            Section("Files") { rows([.safety]) }
        }
    }

    private func rows(_ steps: [BatchStep]) -> some View {
        ForEach(steps) { step in
            HStack {
                Image(systemName: model.isOn(step) ? "circle.fill" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(model.isOn(step) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityLabel(model.isOn(step) ? "On" : "Off")
                Text(step.title)
                Spacer()
                Text(model.summary(of: step))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(model.isUsed(step) ? 1 : 0.4)
            .tag(step)
        }
    }
}
