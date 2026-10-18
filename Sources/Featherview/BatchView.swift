import FeatherviewCore
import SwiftUI

/// The batch window (spec "Window"): images, steps, the selected step's settings; while running,
/// the run view in place of the last two.
struct BatchView: View {
    @Bindable var model: BatchModel
    @State private var namingPreset = false
    @State private var presetName = ""
    @State private var confirmingReplace = false

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
                        BatchStepDetail(step: model.step, model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar { toolbar }
        .frame(minWidth: 960, minHeight: 600)
        .sheet(isPresented: $namingPreset) { presetSheet }
        .alert(model.notice ?? "", isPresented: Binding { model.notice != nil } set: { if !$0 { model.notice = nil } }) {
            Button("OK") { model.notice = nil }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $model.settings.mode) {
                Text("Convert").tag(BatchMode.convert)
                Text("Rename").tag(BatchMode.rename)
                Text("Convert and Rename").tag(BatchMode.convertAndRename)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isRunning)
        }
        ToolbarItem {
            Menu {
                ForEach(model.presetNames, id: \.self) { name in
                    Toggle(name, isOn: Binding { model.loadedPreset == name } set: { _ in model.loadPreset(name) })
                }
                if !model.presetNames.isEmpty { Divider() }
                Button("Save Preset…") {
                    presetName = model.loadedPreset ?? ""
                    namingPreset = true
                }
                Button("Delete Preset") { model.deletePreset() }
                    .disabled(model.loadedPreset == nil)
            } label: {
                if let name = model.loadedPreset {
                    Text(model.presetName == nil ? "\(name) (edited)" : name)
                } else {
                    Text("Presets")
                }
            }
            .disabled(model.isRunning)
        }
        ToolbarItemGroup {
            if model.isRunning {
                if model.isPaused {
                    Button("Resume") { model.resume() }
                } else {
                    Button("Pause") { model.pause() }
                }
                Button("Stop") { model.stop() }
            } else {
                Button("Start") { model.start() }
                    .keyboardShortcut(.defaultAction)
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

/// Task 11 fills this in; Task 10 ships it showing the step's title only.
struct BatchStepDetail: View {
    let step: BatchStep
    @Bindable var model: BatchModel

    var body: some View {
        VStack {
            Text(step.title).font(.title2)
            Spacer()
        }
        .padding()
    }
}
