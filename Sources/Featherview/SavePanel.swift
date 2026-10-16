import AppKit
import FeatherviewCore
import SwiftUI

/// Save As (spec "Menu commands"): the Mac save sheet with a format picker and an Options… button
/// that shows that format's options.
@MainActor
enum SavePanel {
    /// Shows the sheet on `window` (a modal panel without one). The panel's own replace prompt is the
    /// only overwrite confirmation. On Save, the format and its options are remembered.
    static func run(for url: URL, window: NSWindow?) async -> (url: URL, format: OutputFormat, options: FormatOptions)? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = url.deletingLastPathComponent()
        let choice = Choice(format: FormatSettings.lastFormat())
        let setType = { (format: OutputFormat, base: URL) in
            if let type = format.type { panel.allowedContentTypes = [type] }
            // Our extension, or macOS picks the type's preferred one (.pbm for PPM, .jpeg for JPEG).
            panel.nameFieldStringValue = format.fileName(for: base)
        }
        // A new panel's name field says "Untitled", so the first name comes from the image.
        setType(choice.format, url)
        // AppKit, not SwiftUI: in the panel's accessory a SwiftUI picker took the button's clicks, and
        // a SwiftUI sheet from there is unreliable. The options open as a sheet on the panel.
        let formats = FormatRegistry.writable
        let popUp = NSPopUpButton()
        // Item by item: addItems(withTitles:) drops repeated titles, which would shift the indices.
        for format in formats { popUp.menu?.addItem(withTitle: format.name, action: nil, keyEquivalent: "") }
        popUp.selectItem(at: formats.firstIndex(of: choice.format) ?? 0)
        let optionsButton = NSButton(title: String(localized: "Options…"), target: nil, action: nil)
        optionsButton.isEnabled = !choice.format.optionFields.isEmpty
        let formatChanged = Target {
            choice.format = formats[popUp.indexOfSelectedItem]
            choice.options = FormatSettings.options(for: choice.format)
            optionsButton.isEnabled = !choice.format.optionFields.isEmpty
            setType(choice.format, URL(fileURLWithPath: panel.nameFieldStringValue))
        }
        let showOptions = Target {
            let sheet = NSWindow(contentViewController: NSHostingController(rootView: OptionsSheet(choice: choice) {
                if let sheet = panel.attachedSheet { panel.endSheet(sheet) }
            }))
            panel.beginSheet(sheet)
        }
        popUp.target = formatChanged
        popUp.action = #selector(Target.fire)
        optionsButton.target = showOptions
        optionsButton.action = #selector(Target.fire)
        let accessory = NSStackView(views: [NSTextField(labelWithString: String(localized: "Format:")), popUp, optionsButton])
        accessory.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        panel.accessoryView = accessory

        let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
        withExtendedLifetime((formatChanged, showOptions)) {}
        guard response == .OK, let target = panel.url else { return nil }
        FormatSettings.save(choice.options, for: choice.format)
        UserDefaults.standard.set(choice.format.id, forKey: FormatSettings.lastSaveFormat.key)
        return (target, choice.format, choice.options)
    }

    @MainActor @Observable
    final class Choice {
        var format: OutputFormat
        var options: FormatOptions

        init(format: OutputFormat) {
            self.format = format
            options = FormatSettings.options(for: format)
        }
    }

    struct OptionsSheet: View {
        @Bindable var choice: Choice
        let done: () -> Void

        var body: some View {
            VStack(alignment: .trailing) {
                Form {
                    FormatOptionsView(format: choice.format, options: $choice.options)
                }
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(width: 420)
        }
    }

    /// An AppKit control's target that runs a closure.
    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
