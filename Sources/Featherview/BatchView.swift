import FeatherviewCore
import SwiftUI

@MainActor @Observable
final class BatchModel {
    var inputs: [URL] = []
    var outputFolder: URL?
    /// The batch's own format, so Save As and batch don't change each other's (unknown id → JPEG).
    var format: OutputFormat {
        didSet {
            UserDefaults.standard.set(format.id, forKey: "batchFormat")
            options = FormatSettings.options(for: format)
            saved = options
        }
    }
    var options: FormatOptions
    /// The options as last read or written, to tell edits here from a save in another window.
    private var saved: FormatOptions
    var limitSize = false
    var maxDimension = 1920
    var useRename = false
    var renameTemplate = "{name}_{n:3}"
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var results: [BatchResult] = []

    var failures: [BatchResult] { results.filter { $0.status == .failed } }

    init() {
        let format = FormatRegistry.format(id: UserDefaults.standard.string(forKey: "batchFormat") ?? "jpg") ?? .jpeg
        options = FormatSettings.options(for: format)
        saved = FormatSettings.options(for: format)
        self.format = format
    }

    /// Takes options saved by Save As or Settings since, so Convert never writes back a stale copy;
    /// unsaved edits here survive unrelated defaults changes.
    func reloadOptions() {
        let current = FormatSettings.options(for: format)
        guard current != saved else { return }
        options = current
        saved = current
    }

    func run() {
        guard let outputFolder, !inputs.isEmpty, !isRunning else { return }
        FormatSettings.save(options, for: format)
        saved = options
        var settings = BatchSettings()
        settings.mode = useRename ? .convertAndRename : .convert
        settings.formatID = format.id
        settings.options = options
        settings.outputFolder = outputFolder.path
        settings.renamePattern = renameTemplate
        settings.resize.isOn = limitSize
        settings.resize.mode = .longestSide
        settings.resize.side = max(16, maxDimension)
        let job = BatchJob(inputs: inputs.map { BatchInput(url: $0) }, settings: settings)
        isRunning = true
        done = 0
        results = []
        Task {
            results = await BatchConverter.run(job) { _ in
                Task { @MainActor in self.done += 1 }
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
        // Each selection is appended in Finder order; the open panel's own order is arbitrary.
        inputs += panel.urls.filter { !known.contains($0.resolvingSymlinksInPath().path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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

    var body: some View {
        Form {
            Section("Images") {
                LabeledContent("Selected", value: "\(model.inputs.count)")
                HStack {
                    Button("Add Files…") { model.addFiles() }
                    Button("Use Viewer's Folder") { model.inputs = ViewerModel.lastActive.current.list.urls }
                        .disabled(ViewerModel.lastActive.current.list.isEmpty)
                    Button("Clear") { model.inputs = [] }
                }
            }
            Section("Output") {
                Picker("Format", selection: $model.format) {
                    ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
                }
                FormatOptionsView(format: model.format, options: $model.options)
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
                Button("Convert") {
                    // A clicked button doesn't take focus, so a number field still being edited
                    // (target size, longest side) hasn't written its value yet: end editing first.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    model.run()
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.inputs.isEmpty || model.outputFolder == nil)
                if !model.results.isEmpty {
                    Text("\(model.results.count - model.failures.count) converted, \(model.failures.count) failed")
                }
                ForEach(model.failures, id: \.input) { result in
                    Text(result.logLine)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        // The model outlives the window: catch saves from Save As or Settings › Formats.
        .onAppear { model.reloadOptions() }
        .onReceive(defaultsChanged) { _ in model.reloadOptions() }
    }
}
