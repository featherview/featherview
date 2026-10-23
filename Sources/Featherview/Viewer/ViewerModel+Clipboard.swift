import AppKit
import FeatherviewCore

/// File › New from Clipboard (⌘N, Decision 7): an image without a file covers the window's list until it's left,
/// and leaving it asks first.
extension ViewerModel {
    /// The unsaved image's pixel size (full size, upright).
    var unsavedSize: CGSize? { unsaved.map { CGSize(width: $0.width, height: $0.height) } }

    /// A copied image file opens as ⌘O would; else the clipboard's image shows, unsaved.
    func newFromClipboard() {
        let pasteboard = NSPasteboard.general
        let content = ClipboardWatch.content(pasteboard)
        if case .file(let url) = content { return open(url) }
        guard case .data(let type) = content, let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)) else {
            ClipboardWatch.shared.refresh()  // emptied since the menu item was last updated
            return NSSound.beep()
        }
        Task {
            let image = await Task.detached(priority: .userInitiated) { ClipboardImage.image(from: data) }.value
            guard let image else {
                errorMessage = String(localized: "Can't open the image on the clipboard")
                return
            }
            let previous = rotateTask
            // Queued like Trash: a rotation or scan still running would change the list it covers.
            rotateTask = Task {
                await previous?.value
                // An open started while waiting replaces the scan (open() sees no unsaved image yet): the cover
                // waits for whichever is current, so it covers that open's list and nothing lands on it afterwards.
                var waited: Task<Void, Never>?
                while let scan = openTask, scan != waited {
                    waited = scan
                    await scan.value
                }
                // Asked here, not before queuing: a cover still queued has no `unsaved` yet, so a ⌘N after it
                // would replace its image unasked.
                if unsaved != nil, !(await confirmDiscard()) { return }
                cover(with: image)
            }
        }
    }

    private func cover(with picture: CGImage) {
        endSlideshow()
        closeGrid()
        leaveCompare()
        closeChooser()
        destinationPanel = nil
        showInfo = false
        if coveredList == nil { coveredList = list }
        unsaved = picture
        list = ImageList(urls: [])
        // Ends the covered image's decode, animation and navigation; the empty list leaves no picture.
        show()
        pendingChanges = []
        fileInfo = nil
        image = picture
        errorMessage = nil
        setZoom(.fit)
        revealWindow()
    }

    /// The covered list comes back; what shows is up to the caller.
    private func discardUnsaved() {
        unsaved = nil
        list = coveredList ?? list
        coveredList = nil
    }

    /// Runs `action` at once without an unsaved image; with one, after Save… or Don't Save (Cancel: never).
    func leaveUnsaved(then action: @escaping @MainActor () -> Void) {
        guard unsaved != nil else { return action() }
        Task { if await confirmDiscard() { action() } }
    }

    /// Asks about the unsaved image; true once it's saved or dropped (the covered list is back), false to stay.
    func confirmDiscard() async -> Bool {
        guard unsaved != nil else { return true }
        // Already asking, or the save panel is up: a second sheet would queue behind it.
        if window?.attachedSheet != nil { return false }
        let alert = NSAlert()
        alert.messageText = String(localized: "Do you want to save the image from the clipboard?")
        alert.informativeText = String(localized: "If you don't save it, it's gone.")
        alert.addButton(withTitle: String(localized: "Save…"))
        let dontSave = alert.addButton(withTitle: String(localized: "Don't Save"))
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        if let window {
            // A sheet on a minimized window or one on another Space stays out of sight, and a quit would wait on it.
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()  // a quit from the Dock leaves another app in front
        }
        let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        switch response {
        case .alertFirstButtonReturn:
            return await saveUnsaved(thenOpen: false)
        case .alertSecondButtonReturn:
            discardUnsaved()
            return true
        default:
            return false
        }
    }

    /// Save As for the unsaved image: "Untitled" in the list's folder, else Pictures. `thenOpen` (S, ⇧⌘S) shows the
    /// saved file in its folder; from the sheet, the covered list comes back, with the file if saved into its folder.
    /// False if cancelled or failed.
    @discardableResult
    func saveUnsaved(thenOpen: Bool) async -> Bool {
        guard let picture = unsaved else { return true }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard let choice = await SavePanel.run(name: String(localized: "Untitled"),
                                               folder: folder ?? pictures ?? FileManager.default.homeDirectoryForCurrentUser,
                                               window: window) else { return false }
        let target = choice.url
        do {
            try await offPool { try ImageSaver.save(picture, to: target, as: choice.format, options: choice.options) }
        } catch {
            errorMessage = String(localized: "Couldn't save \(target.lastPathComponent)")
            return false
        }
        // It may have replaced a file in the covered list, which comes back below.
        await forgetDecodes(of: target)
        // Another ⌘N or a leave may have come in while the panel was up.
        guard unsaved === picture else { return true }
        discardUnsaved()
        if thenOpen {
            if ImageFormats.isDecodable(target) { open(target) } else { show() }
        } else {
            await addToList(saved: target)
        }
        return true
    }
}
