import AppKit
import FeatherviewCore
import SwiftUI
import UniformTypeIdentifiers

extension BatchCard {
    var title: LocalizedStringKey {
        switch self {
        case .format: "Format and Folder"
        case .name: "Rename"
        case .crop: "Crop"
        case .size: "Resize"
        case .orientation: "Rotate and Flip"
        case .colour: "Colour"
        case .filters: "Filters"
        case .canvas: "Canvas"
        case .border: "Border"
        case .text: "Text"
        case .watermark: "Watermark"
        }
    }
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
        didSet {
            position = Dictionary(inputs.items.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            // Like a settings change: the last run's ticks and names belong to the old list.
            if !isRunning { clearFinished() }
        }
    }
    /// Each input's place in the list: every row asks for its state on each result, so no linear search.
    private var position: [BatchInput: Int] = [:]
    var selection: Set<BatchInput> = []
    var step = BatchCard.format
    private(set) var isRunning = false
    private(set) var isPaused = false
    /// In list order, grows while running.
    private(set) var results: [BatchResult] = []
    /// True between the end of a run and the next settings change or Start: the summary line shows.
    private(set) var isFinished = false
    /// Background folder scans and list loads in flight (the header's spinner).
    private(set) var scans = 0
    /// A short sentence for the user (e.g. missing files of a loaded list); the view shows and clears it.
    var notice: String?

    private(set) var loadedPreset: String?
    private var isEdited = false
    /// nil = unsaved changes since the last load/save.
    var presetName: String? { isEdited ? nil : loadedPreset }
    private(set) var presetNames: [String] = BatchPresets.names()

    private var control = BatchControl()
    private var resultFor: [URL: BatchResult] = [:]
    /// Results not yet handed to the window (see `start`).
    @ObservationIgnored private var pending: [BatchResult] = []
    private var runStart = Date.now
    private var runTotal = 0
    private var saveTask: Task<Void, Never>?
    /// Reads the run's results; ends once every file in flight is committed.
    private var runTask: Task<Void, Never>?

    init() {
        settings = BatchPresets.current()
    }

    // MARK: - Steps column

    func isOn(_ step: BatchCard) -> Bool { step == .size ? settings.resize.isOn : step.isAdded(in: settings) }
    /// Empty for a step that is off.
    func summary(of step: BatchCard) -> String { step.isAdded(in: settings) ? step.summary(in: settings) : "" }

    // MARK: - Running

    var canStart: Bool {
        BatchProgress.canStart(isRunning: isRunning, scans: scans, inputCount: inputs.items.count, settings: settings)
    }

    /// Done files (converted or failed) of the current run.
    var doneCount: Int { results.count }
    var totalCount: Int { runTotal }

    /// Estimated seconds left, once 3 files are done.
    var secondsLeft: Double? {
        guard isRunning else { return nil }
        return BatchProgress.secondsLeft(elapsed: Date.now.timeIntervalSince(runStart),
                                         paused: control.pausedDuration() / .seconds(1), done: doneCount, total: runTotal)
    }

    /// "N converted, M failed" of the last run.
    var summaryLine: String {
        BatchLog.text(results).split(separator: "\n").last.map(String.init) ?? ""
    }

    func state(of input: BatchInput) -> BatchRowState? {
        BatchProgress.rowState(result: resultFor[input.url], index: position[input],
                               isRunning: isRunning, isPaused: isPaused, committed: results.count)
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
            // Results reach the window about four times a second: each update rebuilds every row, and
            // with 10,000 rows one update per file falls behind the converter.
            let flusher = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    flushPending()
                }
            }
            // The stream keeps list order; one Task per result would not.
            for await result in stream { pending.append(result) }
            flusher.cancel()
            flushPending()
            isRunning = false
            isPaused = false
            isFinished = true
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        results.append(contentsOf: pending)
        // One change per flush: each change of an observed property notifies every row.
        var map = resultFor
        for result in pending { map[result.input] = result }
        resultFor = map
        pending = []
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

    /// The last add still running: each add appends after the one before it, so the list keeps the order
    /// the user added in (output numbers follow it), however long each scan takes.
    private var lastAdd: Task<Void, Never>?

    /// Runs `work` off the main thread (it touches the disk), then `append`s its result on the main
    /// actor once every earlier add has appended.
    private func addInOrder<T: Sendable>(_ work: @escaping @Sendable () -> T, append: @escaping (T) -> Void) {
        scans += 1
        let previous = lastAdd
        lastAdd = Task {
            let found = await Task.detached(priority: .userInitiated) { work() }.value
            await previous?.value
            append(found)
            scans -= 1
        }
    }

    /// Scanned and de-duplicated off the main thread, then appended in the order given; folders that
    /// couldn't be listed get a notice.
    private func addInBackground(_ work: @escaping @Sendable () -> (list: BatchInputList, unreadable: [URL])) {
        addInOrder(work) { [self] found in
            inputs.append(found.list)
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
        addInOrder({ () -> (list: BatchInputList, missing: Int)? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var list = BatchInputList()
            let counts = list.load(listText: text)
            return (list, counts.missing)
        }) { [self] loaded in
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
}
