import FeatherviewCore
import SwiftUI

/// Settings (⌘, or P): every setting from spec "Settings". AppKit's toolbar tabs, not SwiftUI's Settings scene,
/// whose window can't animate its height per tab with the content pinned to the top, like other Mac settings windows.
@MainActor
enum SettingsWindow {
    private static var controller: NSWindowController?

    static func show() {
        if controller == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            tabs.add(String(localized: "Browsing"), "photo.on.rectangle", BrowsingSettings())
            tabs.add(String(localized: "Viewer"), "eye", ViewerSettings())
            tabs.add(String(localized: "Full Screen"), "arrow.up.left.and.arrow.down.right", FullScreenSettings())
            tabs.add(String(localized: "Move / Copy"), "folder", MoveCopySettings())
            tabs.add(String(localized: "Open With"), "arrow.up.forward.app", OpenWithSettings())
            tabs.add(String(localized: "Formats"), "doc.badge.gearshape", FormatsSettings())
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            controller = NSWindowController(window: window)
        }
        controller?.showWindow(nil)
    }
}

/// The window takes the selected tab's height, animated with the top edge fixed. The tabs report their
/// height themselves: AppKit's own sizing (from preferredContentSize) jumps.
private final class SettingsTabs: NSTabViewController {
    private var heights: [Int: CGFloat] = [:]

    func add(_ label: String, _ symbol: String, _ view: some View) {
        let index = tabViewItems.count
        let host = NSHostingController(rootView: view
            .formStyle(.grouped)  // wraps long labels instead of clipping them at this width
            .scrollDisabled(true)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .scenePadding()
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { [weak self] in self?.tab(index, height: $0) }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top))  // top stays put while the window's height animates
        host.sizingOptions = []
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        fit()
    }

    private func tab(_ index: Int, height: CGFloat) {
        heights[index] = height
        if index == selectedTabViewItemIndex { fit() }
    }

    private func fit() {
        guard let window = view.window, let height = heights[selectedTabViewItemIndex] else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 560, height: height))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: window.isVisible)
        if !window.isVisible { window.center() }
    }
}

private struct BrowsingSettings: View {
    @AppStorage(AppSettings.pastEnd.key) private var pastEnd = AppSettings.pastEnd.defaultValue
    @AppStorage(AppSettings.showHiddenFiles.key) private var showHidden = AppSettings.showHiddenFiles.defaultValue
    @AppStorage(AppSettings.showNextAfterRemoval.key) private var showNext = AppSettings.showNextAfterRemoval.defaultValue
    @AppStorage(AppSettings.moveSidecars.key) private var sidecars = AppSettings.moveSidecars.defaultValue

    var body: some View {
        Form {
            Picker("Past the end of a folder:", selection: $pastEnd) {
                Text("Show the folder chooser").tag(PastEndBehavior.folderChooser.rawValue)
                Text("Start this folder again").tag(PastEndBehavior.loop.rawValue)
                Text("Stop").tag(PastEndBehavior.stop.rawValue)
            }
            Toggle("Show hidden files", isOn: $showHidden)
            Toggle("Show the next image after moving or trashing one", isOn: $showNext)
            Toggle("Move, copy and trash sidecar files (.xmp, .aae, .thm) with their image", isOn: $sidecars)
        }
    }
}

private struct ViewerSettings: View {
    @AppStorage(AppSettings.backgroundColor.key) private var backgroundHex = AppSettings.backgroundColor.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @AppStorage(AppSettings.zoomStepPercent.key) private var zoomStep = AppSettings.zoomStepPercent.defaultValue

    /// The stored `#RRGGBB` as a colour for the picker; picks are stored back in sRGB.
    private var background: Binding<Color> {
        Binding {
            let c = HexColor.parse(backgroundHex) ?? (0, 0, 0)
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            backgroundHex = HexColor.format(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
        }
    }

    var body: some View {
        Form {
            ColorPicker("Background:", selection: background, supportsOpacity: false)
            Toggle("Checkerboard behind transparent images", isOn: $checkerboard)
            Toggle("Remember the window's size and position", isOn: $rememberFrame)
            Stepper(value: $zoomStep, in: 1...100) {
                Text("Zoom step: \(zoomStep) %")
            }
        }
    }
}

private struct FullScreenSettings: View {
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var template = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue

    var body: some View {
        Form {
            Toggle("Show text over the image", isOn: $showOverlay)
            TextField("Text:", text: $template)
                .disabled(!showOverlay)
            Text("{name} {folder} {index} {count} {size} {date}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Hide the pointer", isOn: $hidePointer)
        }
    }
}

private struct MoveCopySettings: View {
    @AppStorage(AppSettings.askBeforeMoveCopy.key) private var ask = AppSettings.askBeforeMoveCopy.defaultValue
    @State private var slots = DestinationSlots(defaults: .standard)

    var body: some View {
        Form {
            Toggle("Ask before each move or copy", isOn: $ask)
            Section("Folders for F7 (move) and F8 (copy)") {
                ForEach(0..<DestinationSlots.count, id: \.self) { slot in
                    LabeledContent(String(DestinationSlots.keys[slot])) {
                        Text(slots[slot]?.path ?? String(localized: "Empty"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(slots[slot] == nil ? .secondary : .primary)
                        Button("Choose…") { choose(slot) }
                        Button("Clear") { slots = DestinationSlots.update(in: .standard) { $0[slot] = nil } }
                            .disabled(slots[slot] == nil)
                    }
                }
            }
        }
        // The viewer's panel may have changed the slots since this tab was built.
        .onAppear { slots = DestinationSlots(defaults: .standard) }
    }

    private func choose(_ slot: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        slots = DestinationSlots.update(in: .standard) { $0[slot] = url }
    }
}

/// Each format's default options, saved on every change.
private struct FormatsSettings: View {
    @State private var format = FormatSettings.lastFormat()
    @State private var options = FormatSettings.options(for: FormatSettings.lastFormat())

    var body: some View {
        Form {
            Picker("Format:", selection: Binding { format } set: {
                format = $0
                options = FormatSettings.options(for: $0)
            }) {
                ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
            }
            // The options belong to the chosen format: their own group, named after it.
            Section("\(format.name) Options") {
                FormatOptionsView(format: format, options: Binding { options } set: {
                    options = $0
                    FormatSettings.save($0, for: format)
                })
            }
        }
        // Save As and batch save these options too; never write back a stale copy.
        .onReceive(defaultsChanged) { _ in options = FormatSettings.options(for: format) }
    }
}

private struct OpenWithSettings: View {
    @AppStorage(AppSettings.openWith[0].key) private var app1 = ""
    @AppStorage(AppSettings.openWith[1].key) private var app2 = ""
    @AppStorage(AppSettings.openWith[2].key) private var app3 = ""

    var body: some View {
        Form {
            row("⌥1", $app1)
            row("⌥2", $app2)
            row("⌥3", $app3)
        }
    }

    private func row(_ key: String, _ path: Binding<String>) -> some View {
        LabeledContent(key) {
            Text(path.wrappedValue.isEmpty ? "None" : FileManager.default.displayName(atPath: path.wrappedValue))
                .foregroundStyle(path.wrappedValue.isEmpty ? .secondary : .primary)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
            Button("Clear") { path.wrappedValue = "" }
                .disabled(path.wrappedValue.isEmpty)
        }
    }
}
