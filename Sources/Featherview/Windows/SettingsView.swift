import FeatherviewCore
import SwiftUI
import UniformTypeIdentifiers

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
            tabs.fit()  // the first tab's size before the window shows, so opening never animates
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
        let content = view
            .formStyle(.grouped)  // wraps long labels instead of clipping them at this width
            .toggleStyle(.switch)
            .scrollDisabled(true)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
        // Measured up front: a tab reports its height only once shown, so its first switch would jump.
        heights[index] = NSHostingController(rootView: content).sizeThatFits(in: NSSize(width: 560, height: 10_000)).height
        let host = NSHostingController(rootView: content
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { [weak self] in self?.tab(index, height: $0) }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top))  // top stays put while the window's height animates
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 560, height: heights[index] ?? 0)
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
        // Not during the layout pass that reports it: an animated resize there shows only its last frame.
        if index == selectedTabViewItemIndex { DispatchQueue.main.async { self.fit() } }
    }

    func fit() {
        guard let window = view.window, let height = heights[selectedTabViewItemIndex] else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 560, height: height))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: window.isVisible)
        // The tab view controller's view keeps its first fitting width (wider than 560), which pushed the cards off centre.
        window.contentView?.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        if !window.isVisible { window.center() }
    }
}

private struct BrowsingSettings: View {
    @AppStorage(AppSettings.pastEnd.key) private var pastEnd = AppSettings.pastEnd.defaultValue
    @AppStorage(AppSettings.showHiddenFiles.key) private var showHidden = AppSettings.showHiddenFiles.defaultValue
    @AppStorage(AppSettings.showNextAfterRemoval.key) private var showNext = AppSettings.showNextAfterRemoval.defaultValue
    @AppStorage(AppSettings.moveSidecars.key) private var sidecars = AppSettings.moveSidecars.defaultValue
    @AppStorage(AppSettings.checkForUpdates.key) private var checkForUpdates = AppSettings.checkForUpdates.defaultValue
    @State private var apps: [UTType: String] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(DefaultViewer.commonTypes, id: \.self) { type in
                    LabeledContent(type.localizedDescription ?? type.identifier) {
                        HStack {
                            Text(apps[type] ?? String(localized: "No app")).foregroundStyle(Theme.labelSecondary)
                            Button("Use Featherview") { Task { await DefaultViewerOffer.claim(type); refresh() } }
                                .disabled(DefaultViewerOffer.opensWithFeatherview(type))
                        }
                    }
                }
            } header: {
                Text("Default app")
            } footer: {
                Text("For any other type, open an image of it and choose File › Always Open with Featherview.")
            }
            Section("Folders") {
                Picker("Past the end of a folder:", selection: $pastEnd) {
                    Text("Show the folder chooser").tag(PastEndBehavior.folderChooser.rawValue)
                    Text("Start this folder again").tag(PastEndBehavior.loop.rawValue)
                    Text("Stop").tag(PastEndBehavior.stop.rawValue)
                }
                Toggle("Show hidden files", isOn: $showHidden)
            }
            Section("After a move or Move to Trash") {
                Toggle("Show the next image after moving or trashing one", isOn: $showNext)
                Toggle("Move, copy and trash sidecar files (.xmp, .aae, .thm) with their image", isOn: $sidecars)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        apps = Dictionary(uniqueKeysWithValues: DefaultViewer.commonTypes.compactMap { type in
            DefaultViewerOffer.appName(for: type).map { (type, $0) }
        })
    }
}

private struct ViewerSettings: View {
    @AppStorage(AppSettings.appearance.key) private var appearance = AppSettings.appearance.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @AppStorage(AppSettings.zoomStepPercent.key) private var zoomStep = AppSettings.zoomStepPercent.defaultValue
    @AppStorage(AppSettings.hideBarsWhileViewing.key) private var hideBars = AppSettings.hideBarsWhileViewing.defaultValue

    var body: some View {
        Form {
            Section("Appearance") {
                AppearancePicker(selection: $appearance)
                    .onChange(of: appearance) { Theme.apply(AppearanceMode(stored: $1)) }
            }
            Section("Window") {
                Toggle("Checkerboard behind transparent images", isOn: $checkerboard)
                Toggle("Remember the window's size and position", isOn: $rememberFrame)
                Stepper(value: $zoomStep, in: 1...100) {
                    Text("Zoom step: \((Double(zoomStep) / 100).formatted(.percent))")
                }
            }
            Section("Bars") {
                Toggle("Hide toolbar and status bar while viewing", isOn: $hideBars)
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
            Section("Overlay") {
                Toggle("Show text over the image", isOn: $showOverlay)
                TextField("Text:", text: $template)
                    .disabled(!showOverlay)
                Text("{name} {folder} {path} {index} {count} {size} {date}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pointer") {
                Toggle("Hide the pointer", isOn: $hidePointer)
            }
        }
    }
}

private struct MoveCopySettings: View {
    @AppStorage(AppSettings.askBeforeMoveCopy.key) private var ask = AppSettings.askBeforeMoveCopy.defaultValue
    @State private var slots = DestinationSlots(defaults: .standard)

    var body: some View {
        Form {
            Section("Folders for F7 (move) and F8 (copy)") {
                Toggle("Ask before each move or copy", isOn: $ask)
                ForEach(0..<DestinationSlots.count, id: \.self) { slot in
                    LabeledContent(String(DestinationSlots.keys[slot])) {
                        Text(slots[slot]?.path ?? String(localized: "Empty", comment: "Folder slot with no folder chosen"))
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
        if let chosen = ViewerModel.chooseFolder(for: slot, in: slots) { slots = chosen }
    }
}

/// Each format's default options, saved on every change.
private struct FormatsSettings: View {
    @State private var format = FormatSettings.lastFormat()
    @State private var options = FormatSettings.options(for: FormatSettings.lastFormat())

    var body: some View {
        Form {
            // Pick the format first; its options follow in their own group, named after it.
            Section {
                Picker("Format:", selection: Binding { format } set: {
                    format = $0
                    options = FormatSettings.options(for: $0)
                }) {
                    ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
                }
            } footer: {
                Text("Save As and the batch window start with these options for each format.")
                    .foregroundStyle(.secondary)
            }
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
            Section("Apps for ⌥1, ⌥2 and ⌥3") {
                row("⌥1", $app1)
                row("⌥2", $app2)
                row("⌥3", $app3)
            }
        }
    }

    private func row(_ key: String, _ path: Binding<String>) -> some View {
        LabeledContent(key) {
            Text(path.wrappedValue.isEmpty ? String(localized: "None") : FileManager.default.displayName(atPath: path.wrappedValue))
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
