import FeatherviewCore
import SwiftUI

/// Settings (⌘, or P): every setting from spec "Settings" except Formats (milestone 3).
struct SettingsView: View {
    var body: some View {
        TabView {
            BrowsingSettings().tabItem { Label("Browsing", systemImage: "photo.on.rectangle") }
            ViewerSettings().tabItem { Label("Viewer", systemImage: "eye") }
            FullScreenSettings().tabItem { Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") }
            MoveCopySettings().tabItem { Label("Move / Copy", systemImage: "folder") }
            OpenWithSettings().tabItem { Label("Open With", systemImage: "arrow.up.forward.app") }
        }
        .frame(width: 520)
        .scenePadding()
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
                        Text(slots[slot]?.path ?? "Empty")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(slots[slot] == nil ? .secondary : .primary)
                        Button("Choose…") { choose(slot) }
                        Button("Clear") { slots[slot] = nil; slots.save(to: .standard) }
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
        slots[slot] = url
        slots.save(to: .standard)
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
