import AppKit
import FeatherviewCore
import SwiftUI

/// Save As (spec "Menu commands"): the Mac save sheet with a format picker and that format's options.
@MainActor
enum SavePanel {
    /// Shows the sheet on `window` (a modal panel without one). The panel's own replace prompt is the
    /// only overwrite confirmation. On Save, the format and its options are remembered.
    static func run(for url: URL, window: NSWindow?) async -> (url: URL, format: OutputFormat, options: FormatOptions)? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = url.deletingLastPathComponent()
        let choice = Choice(format: FormatSettings.lastFormat())
        let setType = { (format: OutputFormat) in
            // macOS then puts the format's extension on the name.
            if let type = format.type { panel.allowedContentTypes = [type] }
        }
        setType(choice.format)
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent
        let accessory = NSHostingView(rootView: Accessory(choice: choice, formatChanged: setType))
        accessory.sizingOptions = [.intrinsicContentSize]
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory

        let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
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

    struct Accessory: View {
        @Bindable var choice: Choice
        let formatChanged: (OutputFormat) -> Void

        var body: some View {
            Form {
                Picker("Format:", selection: $choice.format) {
                    ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
                }
                FormatOptionsView(format: choice.format, options: $choice.options)
            }
            .onChange(of: choice.format) { _, format in
                choice.options = FormatSettings.options(for: format)
                formatChanged(format)
            }
            .padding()
            .frame(width: 420)
        }
    }
}
