import AppKit
import FeatherviewCore
import SwiftUI

/// The file name as a text field: the part before the extension selected, as in Finder. Return and losing focus
/// commit, Esc cancels. `onCommit` false keeps it open (Return) or closes it with the message showing (focus lost).
struct RenameField: NSViewRepresentable {
    @Binding var text: String
    /// In the title the field is as wide as the name; in the sheet it fills the width it's given.
    var fillsWidth = false
    let onCommit: () async -> Bool
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingField(string: text)
        field.font = Theme.renameFont
        field.textColor = Theme.renameText
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        let height = field.intrinsicContentSize.height
        if fillsWidth { return CGSize(width: proposal.width ?? Theme.renameSheetWidth, height: height) }
        let name = (text as NSString).size(withAttributes: [.font: Theme.renameFont]).width + Theme.renameFieldInset
        return CGSize(width: min(max(name, Theme.renameFieldMinWidth), proposal.width ?? .infinity), height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        /// Committing or done: the end of editing that follows (the field leaving the window) commits nothing more.
        private var settled = false

        init(parent: RenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                commit(closesOnRefusal: false)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                settled = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ note: Notification) {
            commit(closesOnRefusal: true)
        }

        private func commit(closesOnRefusal: Bool) {
            guard !settled else { return }
            settled = true
            Task {
                let done = await parent.onCommit()
                if !done, closesOnRefusal { parent.onCancel() }
                settled = done || closesOnRefusal
            }
        }
    }
}

/// Takes the keyboard once it's in a window, and selects the name without its extension whenever it gains focus.
private final class FocusingField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // After SwiftUI's own focus pass for this update, which would otherwise keep the viewer focused.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        currentEditor()?.selectedRange = FileRenamer.stemRange(of: stringValue)
        return true
    }
}

/// Rename with the toolbar hidden or in full screen, where the title isn't there to edit.
struct RenameSheet: View {
    let model: ViewerModel
    @State private var text: String

    init(model: ViewerModel) {
        self.model = model
        _text = State(initialValue: model.list.current?.lastPathComponent ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.headline)
            RenameField(text: $text, fillsWidth: true, onCommit: { await model.commitRename(text) }, onCancel: model.cancelRename)
                .frame(width: Theme.renameSheetWidth)
            if let message = model.errorMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelRename() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { Task { _ = await model.commitRename(text) } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
