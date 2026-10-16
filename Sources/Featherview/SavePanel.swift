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
        let accessory = NSHostingView(rootView: Accessory(choice: choice) { setType($0, URL(fileURLWithPath: panel.nameFieldStringValue)) })
        accessory.sizingOptions = [.intrinsicContentSize]
        // Auto Layout, not a fixed frame: the panel sizes itself to the accessory.
        accessory.translatesAutoresizingMaskIntoConstraints = false
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
        @State private var showingOptions = false

        var body: some View {
            // The options sit behind a button (maintainer, 2026-10-16), so the panel keeps one size.
            HStack {
                Picker("Format:", selection: $choice.format) {
                    ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
                }
                Button("Options…") { showingOptions = true }
                    .disabled(choice.format.optionFields.isEmpty)
            }
            .sheet(isPresented: $showingOptions) {
                VStack(alignment: .trailing) {
                    Form {
                        FormatOptionsView(format: choice.format, options: $choice.options)
                    }
                    Button("Done") { showingOptions = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                .frame(width: 420)
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
