import AppKit
import FeatherviewCore

/// Rename (F2, Decision 2): the name in the title becomes a field; the file is renamed in place, never overwriting,
/// and the picture stays on screen without a new decode.
extension ViewerModel {
    func beginRename() {
        guard availability.canChangeFile, !renaming, let url = list.current else { return }
        renamingURL = url
        errorMessage = nil
        renamingInSheet = isFullScreen || UserDefaults.standard.bool(forKey: toolbarHiddenKey)
        renaming = true
    }

    func cancelRename() {
        renaming = false
        renamingURL = nil
        errorMessage = nil
    }

    /// Renames the file F2 was pressed on to `typed`; false keeps the field open (the message says why).
    func commitRename(_ typed: String) async -> Bool {
        guard renaming, !renameBusy, let url = renamingURL, !list.isHolding else { return true }
        renameBusy = true
        defer { renameBusy = false }
        var name = FileRenamer.trimmed(typed)
        if name == url.lastPathComponent || FileRenamer.check(name) == .empty {
            cancelRename()
            return true
        }
        if let problem = FileRenamer.check(name) {
            errorMessage = problem.message
            return false
        }
        if let change = FileRenamer.extensionChange(from: url, to: name), !(await usesNewExtension(change)) {
            let stem = (name as NSString).deletingPathExtension
            name = change.old.isEmpty ? stem : "\(stem).\(change.old)"
            if name == url.lastPathComponent {
                cancelRename()
                return true
            }
        }
        let target = name
        let withSidecars = AppSettings.moveSidecars.value()
        let previous = rotateTask
        let scan = openTask
        // Queued like Trash: a rotation would write the old path back, the scan's list would bring the old name back.
        let rename = Task { () -> Bool in
            await previous?.value
            await scan?.value
            guard list.urls.contains(url) else { return true }  // trashed or moved meanwhile, or another folder opened
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FileRenamer.rename(url, to: target, sidecars: withSidecars ? Sidecars.files(for: url) : []) }
            }.value
            switch result {
            case .success(let renamed):
                await moved(url, to: renamed)
                return true
            case .failure(let problem as RenameProblem):
                errorMessage = problem.message
                return false
            case .failure:
                errorMessage = String(localized: "Couldn't rename \(url.lastPathComponent)")
                return false
            }
        }
        rotateTask = Task { _ = await rename.value }
        let done = await rename.value
        if done { cancelRename() }
        return done
    }

    /// Finder's question for a changed extension; true for "Use .new".
    private func usesNewExtension(_ change: (old: String, new: String)) async -> Bool {
        let alert = NSAlert()
        if change.new.isEmpty {
            alert.messageText = String(localized: "Are you sure you want to remove the extension “.\(change.old)”?")
        } else {
            alert.messageText = String(localized: "Are you sure you want to change the extension from “.\(change.old)” to “.\(change.new)”?")
        }
        alert.informativeText = String(localized: "The image may then open in another app, or not at all.")
        alert.addButton(withTitle: String(localized: "Keep .\(change.old)"))
        alert.addButton(withTitle: change.new.isEmpty ? String(localized: "Remove") : String(localized: "Use .\(change.new)"))
        // In the sheet, the viewer window already has RenameSheet attached: a second sheet there would wait behind it.
        let response = if let window { await alert.beginSheetModal(for: window.attachedSheet ?? window) } else { alert.runModal() }
        return response == .alertSecondButtonReturn
    }

    /// The renamed file takes the old one's place: its decode, details and position follow, nothing is read again
    /// but its sort value.
    private func moved(_ old: URL, to new: URL) async {
        guard old != new else { return }
        let decoded = ready[old]
        let info = knownInfo[old]
        // Old path's decodes and details go; the Info panel rereads (fileRevision).
        await forgetDecodes(of: old)
        ready[new] = decoded
        knownInfo[new] = info?.moved(to: new)
        if fileInfo?.url == old { fileInfo = fileInfo?.moved(to: new) }
        // The picture on screen is the renamed file's: a zoom or rotation after this mustn't count as another file.
        if showing?.url == old { showing?.url = new }
        if onScreen?.url == old { onScreen?.url = new }
        sortValues[old] = nil
        await readSortValues(for: [new])
        guard list.urls.contains(old) else { return }  // another folder opened while the value was read
        relist(list.urls.map { $0 == old ? new : $0 })
        // relist holds a current file it no longer finds: here it is the same file under its new name.
        if list.current == old, list.select(new) { focusDecodes() }
    }
}
