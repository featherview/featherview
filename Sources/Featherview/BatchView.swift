import FeatherviewCore
import SwiftUI

@MainActor @Observable
final class BatchModel {
    var inputs: [URL] = []
    var outputFolder: URL?
    var format = OutputFormat.jpeg
    var quality = BatchJob.defaultQuality
    var limitSize = false
    var maxDimension = 1920
    var useRename = false
    var renameTemplate = "{name}_{n:3}"
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var results: [BatchResult] = []

    var failures: [BatchResult] { results.filter { $0.error != nil } }

    func run() {
        guard let outputFolder, !inputs.isEmpty, !isRunning else { return }
        let job = BatchJob(
            inputs: inputs, outputFolder: outputFolder, format: format, quality: quality,
            maxDimension: limitSize ? max(16, maxDimension) : nil,
            rename: useRename ? RenamePattern(renameTemplate) : nil)
        isRunning = true
        done = 0
        results = []
        Task {
            results = await BatchConverter.run(job) { done, _ in
                Task { @MainActor in self.done = max(self.done, done) }
            }
            isRunning = false
        }
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        // A file added twice would be converted twice.
        let known = Set(inputs.map { $0.resolvingSymlinksInPath().path })
        inputs += panel.urls.filter { !known.contains($0.resolvingSymlinksInPath().path) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputFolder = panel.url }
    }
}

struct BatchView: View {
    @Bindable var model: BatchModel
    let viewer: ViewerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Images") {
                LabeledContent("Selected", value: "\(model.inputs.count)")
                HStack {
                    Button("Add Files…") { model.addFiles() }
                    Button("Use Viewer's Folder") { model.inputs = viewer.list.urls }
                        .disabled(viewer.list.isEmpty)
                    Button("Clear") { model.inputs = [] }
                }
            }
            Section("Output") {
                Picker("Format", selection: $model.format) {
                    ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()) }
                }
                if model.format.isLossy {
                    Slider(value: $model.quality, in: 0.01...1, step: 0.01) {
                        Text("Quality \(Int((model.quality * 100).rounded()))")
                    }
                }
                Toggle("Limit size", isOn: $model.limitSize)
                if model.limitSize {
                    TextField("Longest side (px)", value: $model.maxDimension, format: .number.grouping(.never))
                }
                Toggle("Rename", isOn: $model.useRename)
                if model.useRename {
                    TextField("Pattern", text: $model.renameTemplate)
                    Text("{name} = original name · {n} = number · {n:3} = 001")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Folder") {
                    Text(model.outputFolder?.path ?? "None").lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { model.chooseOutputFolder() }
                }
            }
            Section {
                if model.isRunning {
                    ProgressView(value: Double(model.done), total: Double(max(model.inputs.count, 1)))
                }
                Button("Convert") { model.run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.inputs.isEmpty || model.outputFolder == nil)
                if !model.results.isEmpty {
                    Text("\(model.results.count - model.failures.count) converted, \(model.failures.count) failed")
                }
                ForEach(model.failures, id: \.input) { result in
                    Text("\(result.input.lastPathComponent): \(result.error ?? "")")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        // The viewer window may never have appeared (e.g. only this window was restored).
        .onAppear { viewer.revealWindow = { [openWindow] in openWindow(id: "viewer") } }
    }
}
