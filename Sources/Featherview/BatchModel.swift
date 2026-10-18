import AppKit
import FeatherviewCore
import SwiftUI
import UniformTypeIdentifiers

/// The batch window's steps column (spec "Window"): output, rename, the operations in spec order, safety.
enum BatchStep: String, CaseIterable, Identifiable {
    case output, rename, crop, resize, orientation, colour, filters, canvas, border, text, watermark, safety

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .output: "Format and Folder"
        case .rename: "Rename"
        case .crop: "Crop"
        case .resize: "Resize"
        case .orientation: "Rotate and Flip"
        case .colour: "Colour"
        case .filters: "Filters"
        case .canvas: "Canvas"
        case .border: "Border"
        case .text: "Text"
        case .watermark: "Watermark"
        case .safety: "Safety and Dates"
        }
    }

    static let operations: [BatchStep] = [.crop, .resize, .orientation, .colour, .filters, .canvas, .border, .text, .watermark]
}

/// An input row's state during and after a run.
enum BatchRowState: Equatable {
    case waiting, working
    case done(String)
    case failed(String)
}

@MainActor @Observable
final class BatchModel {
    /// Saved (debounced) on every change; a change also clears the last run's summary and edits the loaded preset.
    var settings: BatchSettings {
        didSet {
            guard settings != oldValue else { return }
            isEdited = true
            if !isRunning { clearFinished() }
            scheduleSave()
        }
    }
    var inputs = BatchInputList() {
        didSet { if inputs != oldValue { updateTotalBytes() } }
    }
    var selection: Set<BatchInput> = []
    var step = BatchStep.output
    private(set) var isRunning = false
    private(set) var isPaused = false
    /// In list order, grows while running.
    private(set) var results: [BatchResult] = []
    /// True between the end of a run and the next settings change or Start: the summary line shows.
    private(set) var isFinished = false
    /// Background folder scans and list loads in flight (the header's spinner).
    private(set) var scans = 0
    /// Sum of the inputs' file sizes; nil while it's being read.
    private(set) var totalBytes: Int?
    /// A short sentence for the user (e.g. missing files of a loaded list); the view shows and clears it.
    var notice: String?

    private(set) var loadedPreset: String?
    private var isEdited = false
    /// nil = unsaved changes since the last load/save.
    var presetName: String? { isEdited ? nil : loadedPreset }
    private(set) var presetNames: [String] = BatchPresets.names()

    private var control = BatchControl()
    private var resultFor: [URL: BatchResult] = [:]
    private var runStart = Date.now
    private var runTotal = 0
    private var saveTask: Task<Void, Never>?
    private var bytesTask: Task<Void, Never>?
    /// Reads the run's results; ends once every file in flight is committed.
    private var runTask: Task<Void, Never>?

    init() {
        settings = BatchPresets.current()
    }

    // MARK: - Steps column

    func isUsed(_ step: BatchStep) -> Bool {
        switch step {
        case .rename: settings.mode != .convert
        case _ where BatchStep.operations.contains(step): settings.mode != .rename
        default: true
        }
    }

    func isOn(_ step: BatchStep) -> Bool {
        let s = settings
        switch step {
        case .output: return true
        case .rename: return s.mode != .convert
        case .crop: return s.crop.isOn
        case .resize: return s.resize.isOn
        case .orientation: return s.orientation.isOn
        case .colour: return s.colour.isOn
        case .filters: return s.filters.isOn
        case .canvas: return s.canvas.isOn
        case .border: return s.border.isOn
        case .text: return s.text.isOn
        case .watermark: return s.watermark.isOn
        case .safety:
            let f = s.safety
            return f.replaceExisting || f.trashOriginals || f.keepDates || f.recreateSubfolders
        }
    }

    /// "HEIC", "2048", "on", "" (off or unused).
    func summary(of step: BatchStep) -> String {
        guard isUsed(step) else { return "" }
        switch step {
        case .output:
            return settings.mode == .rename ? String(localized: "Same format") : settings.format.name
        case .rename:
            return settings.renamePattern
        case .resize:
            guard settings.resize.isOn else { return "" }
            let r = settings.resize
            switch r.mode {
            case .longestSide, .shortestSide: return "\(r.side)"
            case .widthHeight:
                return String(localized: "\(r.width.map(String.init) ?? "–") × \(r.height.map(String.init) ?? "–")")
            case .megapixels: return String(localized: "\(r.megapixels.formatted()) MP")
            case .percent: return String(localized: "\(r.percentWidth.formatted()) %")
            }
        default:
            return isOn(step) ? String(localized: "on") : ""
        }
    }

    // MARK: - Running

    var canStart: Bool {
        // A scan still in flight would append files the run never sees.
        !isRunning && scans == 0 && !inputs.items.isEmpty && (settings.mode == .rename || !settings.outputFolder.isEmpty)
    }

    /// Done files (converted or failed) of the current run.
    var doneCount: Int { results.count }
    var totalCount: Int { runTotal }

    /// Estimated seconds left, once 3 files are done.
    var secondsLeft: Double? {
        guard isRunning, doneCount >= 3, doneCount < runTotal else { return nil }
        let active = Date.now.timeIntervalSince(runStart) - control.pausedDuration() / .seconds(1)
        return active / Double(doneCount) * Double(runTotal - doneCount)
    }

    /// "N converted, M failed" of the last run.
    var summaryLine: String {
        BatchLog.text(results).split(separator: "\n").last.map(String.init) ?? ""
    }

    func state(of input: BatchInput) -> BatchRowState? {
        if let result = resultFor[input.url] {
            switch result.status {
            case .converted: return .done(result.output?.lastPathComponent ?? "")
            case .failed: return .failed(result.logLine)
            case .notStarted: return nil
            }
        }
        guard isRunning else { return nil }
        // shortcut: the converter doesn't report starts; files run in list order, so the next
        // `workers` uncommitted rows are shown working. Exact once the converter reports starts.
        guard let index = inputs.items.firstIndex(of: input) else { return .waiting }
        return !isPaused && index < results.count + max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
            ? .working : .waiting
    }

    func start() {
        guard canStart else { return }
        // A clicked button doesn't take focus: a field still being edited hasn't written its value yet.
        NSApp.keyWindow?.makeFirstResponder(nil)
        clearFinished()
        let job = BatchJob(inputs: inputs.items, settings: settings)
        let control = BatchControl()
        self.control = control
        runTotal = job.inputs.count
        runStart = .now
        isRunning = true
        isPaused = false
        let (stream, continuation) = AsyncStream.makeStream(of: BatchResult.self)
        Task.detached {
            _ = await BatchConverter.run(job, control: control) { continuation.yield($0) }
            continuation.finish()
        }
        runTask = Task {
            // The stream keeps list order; one Task per result would not.
            for await result in stream {
                results.append(result)
                resultFor[result.input] = result
            }
            isRunning = false
            isPaused = false
            isFinished = true
        }
    }

    func pause() { control.pause(); isPaused = control.isPaused }
    func resume() { control.resume(); isPaused = false }
    func stop() { control.stop(); isPaused = false }

    /// Stops the run and returns once the files in flight are committed (no temp file is left).
    func stopAndWait() async {
        stop()
        await runTask?.value
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BatchLog.text(results), forType: .string)
    }

    private func clearFinished() {
        guard isFinished || !results.isEmpty else { return }
        results = []
        resultFor = [:]
        isFinished = false
    }

    // MARK: - Presets

    func loadPreset(_ name: String) {
        guard let preset = BatchPresets.load(name) else { return refreshPresets() }
        settings = preset
        loadedPreset = name
        isEdited = false
    }

    /// True when saving under `name` would replace a different preset: ask first.
    func replacesAnotherPreset(_ name: String) -> Bool {
        BatchPresets.replacesAnother(name, loaded: loadedPreset)
    }

    func savePreset(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BatchPresets.save(name, settings) else {
            notice = String(localized: "Can't save the preset \(name)")
            return
        }
        loadedPreset = name
        isEdited = false
        refreshPresets()
    }

    func deletePreset() {
        guard let name = loadedPreset else { return }
        guard BatchPresets.delete(name) else {
            notice = String(localized: "Can't delete the preset \(name)")
            return
        }
        loadedPreset = nil
        refreshPresets()
    }

    private func refreshPresets() { presetNames = BatchPresets.names() }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            BatchPresets.saveCurrent(settings)
        }
    }

    /// Writes pending settings now (the app is quitting).
    func saveNow() {
        saveTask?.cancel()
        BatchPresets.saveCurrent(settings)
    }

    // MARK: - Inputs

    /// Scanned and de-duplicated off the main thread (both touch the disk), then appended in the
    /// order given; folders that couldn't be listed get a notice.
    private func addInBackground(_ work: @escaping @Sendable () -> (list: BatchInputList, unreadable: [URL])) {
        scans += 1
        Task {
            let found = await Task.detached(priority: .userInitiated) { work() }.value
            inputs.append(found.list)
            scans -= 1
            if let first = found.unreadable.first {
                let name = first.lastPathComponent
                notice = found.unreadable.count == 1
                    ? String(localized: "Can't open \(name)")
                    : String(localized: "Can't open \(name) and \(found.unreadable.count - 1) more folders")
            }
        }
    }

    func add(files: [URL]) {
        addInBackground {
            var list = BatchInputList()
            list.add(files: files)
            return (list, [])
        }
    }

    func add(folder: URL, subfolders: Bool) {
        addInBackground {
            do { return (BatchInputList(try BatchInputList.scan(folder: folder, subfolders: subfolders)), []) }
            catch { return (BatchInputList(), [folder]) }
        }
    }

    /// Dropped files and folders; folders add with their subfolders.
    func add(dropped urls: [URL]) {
        addInBackground { BatchInputList.scan(dropped: urls) }
    }

    func addFilesPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(files: panel.urls)
    }

    func addFolderPanel(subfolders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(folder: url, subfolders: subfolders)
    }

    func useViewersFolder() {
        add(files: ViewerModel.lastActive.current.list.urls)
    }

    private var selectedOffsets: IndexSet {
        IndexSet(inputs.items.indices.filter { selection.contains(inputs.items[$0]) })
    }

    func removeSelected() {
        inputs.remove(at: selectedOffsets)
        selection = []
    }

    func removeAll() {
        inputs.removeAll()
        selection = []
    }

    func sortByName() { inputs.sortByName() }

    func moveSelected(by delta: Int) { inputs.move(selectedOffsets, by: delta) }

    func saveListPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(localized: "Batch List.txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try inputs.listText().write(to: url, atomically: true, encoding: .utf8) }
        catch { notice = String(localized: "Can't save \(url.lastPathComponent)") }
    }

    func loadListPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scans += 1
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (list: BatchInputList, missing: Int)? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                var list = BatchInputList()
                let counts = list.load(listText: text)
                return (list, counts.missing)
            }.value
            scans -= 1
            guard let loaded else {
                notice = String(localized: "Can't open \(url.lastPathComponent)")
                return
            }
            inputs.append(loaded.list)
            if loaded.missing > 0 {
                notice = String(localized: "\(loaded.missing) files of \(url.lastPathComponent) no longer exist")
            }
        }
    }

    private func updateTotalBytes() {
        bytesTask?.cancel()
        totalBytes = nil
        let items = inputs.items
        bytesTask = Task {
            let total = await Task.detached(priority: .utility) {
                items.reduce(0) { $0 + $1.fileSize() }
            }.value
            guard !Task.isCancelled else { return }
            totalBytes = total
        }
    }
}
