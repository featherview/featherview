import AppKit
import FeatherviewCore
import SwiftUI

/// Image › All Metadata… (spec "All Metadata window"): one utility window that follows the current image
/// of the frontmost viewer. A window, not a sheet, so the viewer's arrow keys keep browsing.
@MainActor enum AllMetadataWindow {
    fileprivate static var panel: NSPanel?

    static func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        attachContent(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The panel with its view, not yet on screen; the panel (and its frame) outlives closing, the view doesn't.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 360, height: 280)
        attachContent(panel)
        panel.center()
        // Closing drops the view: it follows the current image and would read every image's metadata while
        // browsing, for a window nobody sees. show() attaches a new one.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) {
            [weak panel] _ in MainActor.assumeIsolated { panel?.contentViewController = nil }
        }
        return panel
    }

    static func attachContent(_ panel: NSPanel) {
        guard panel.contentViewController == nil else { return }
        let frame = panel.frame
        panel.contentViewController = NSHostingController(rootView: AllMetadataView())
        panel.setFrame(frame, display: false)
    }
}

private struct AllMetadataView: View {
    private enum Field { case search, list }
    private struct Key: Hashable { var url: URL?; var revision: Int }

    /// nil without an image or before its first read.
    @State private var catalog: MetadataCatalog?
    @State private var query = ""
    @State private var selection: Set<MetadataEntry.ID> = []
    @State private var collapsed: Set<MetadataSection.ID> = []
    @FocusState private var focus: Field?

    private var viewer: ViewerModel { ViewerModel.lastActive.current }
    private var key: Key { Key(url: viewer.list.current, revision: viewer.fileRevision) }
    private var sections: [MetadataSection] { catalog?.sections ?? [] }
    private var shown: [MetadataSection] { catalog?.filtered(query).sections ?? [] }
    /// The rows the list shows, in order: open sections only.
    private var visibleEntries: [MetadataEntry] {
        shown.filter { !collapsed.contains($0.id) }.flatMap(\.entries)
    }
    private var selectedEntries: [MetadataEntry] {
        shown.flatMap(\.entries).filter { selection.contains($0.id) }
    }
    private var title: String {
        guard let name = key.url?.lastPathComponent else { return String(localized: "All Metadata") }
        return String(localized: "\(name) — All Metadata")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.panelGap) {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .search)
                    .onSubmit {
                        // Return moves to the first match.
                        guard let first = visibleEntries.first else { return }
                        selection = [first.id]
                        focus = .list
                    }
                Button("Copy") { copy(selectedEntries) }
                    .disabled(selection.isEmpty)
                Button("Copy All") { copy(sections.flatMap(\.entries)) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(sections.isEmpty)
                // ⌘F: no visible control; the search field shows where it lands.
                Button("Search") { focus = .search }
                    .keyboardShortcut("f")
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(Theme.panelGap)
            Divider()
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(shown) { section in
                        Section(isExpanded: expanded(section.id)) {
                            ForEach(section.entries) { MetadataRow(entry: $0) }
                        } header: {
                            HStack {
                                Text(verbatim: section.id)
                                Spacer()
                                Text(verbatim: section.entries.count.formatted())
                                    .foregroundStyle(Theme.labelSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .tint(Theme.accent)
                .focused($focus, equals: .list)
                .onCopyCommand { MetadataCatalog.copyText(selectedEntries).map { [NSItemProvider(object: $0 as NSString)] } ?? [] }
                .onKeyPress(.leftArrow) { setGroupOfSelection(open: false) }
                .onKeyPress(.rightArrow) { setGroupOfSelection(open: true) }
                .onKeyPress(.home) { select(visibleEntries.first, proxy) }
                .onKeyPress(.end) { select(visibleEntries.last, proxy) }
                .overlay {
                    if shown.isEmpty {
                        Text(query.isEmpty ? "No metadata" : "No matches")
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }
            }
            Divider()
            footer
                .font(.callout)
                .foregroundStyle(Theme.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.panelGap)
        }
        .onKeyPress(.escape) {
            // Esc clears the search, then closes the window.
            if query.isEmpty { AllMetadataWindow.panel?.close() } else { query = "" }
            return .handled
        }
        .onChange(of: title, initial: true) { AllMetadataWindow.panel?.title = title }
        .task(id: key) {
            guard let url = key.url else { catalog = nil; return }
            let read = await Task.detached(priority: .userInitiated) { MetadataCatalog.read(url) }.value
            // A later image's read replaced this one: its task was cancelled.
            guard !Task.isCancelled else { return }
            catalog = read
            selection = []
        }
    }

    @ViewBuilder private var footer: some View {
        let entries = shown.reduce(0) { $0 + $1.entries.count }
        let hidden = catalog?.hiddenCount ?? 0
        if hidden > 0 {
            Text("\(entries) entries · \(hidden) internal entries hidden")
        } else {
            Text("\(entries) entries")
        }
    }

    private func expanded(_ id: MetadataSection.ID) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(id) },
                set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } })
    }

    /// ← / →: closes or opens the group of the selected row.
    private func setGroupOfSelection(open: Bool) -> KeyPress.Result {
        guard let section = shown.first(where: { $0.entries.contains { selection.contains($0.id) } }) else { return .ignored }
        expanded(section.id).wrappedValue = open
        return .handled
    }

    private func select(_ entry: MetadataEntry?, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let entry else { return .ignored }
        selection = [entry.id]
        proxy.scrollTo(entry.id)
        return .handled
    }

    private func copy(_ entries: [MetadataEntry]) {
        guard let text = MetadataCatalog.copyText(entries) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A readable name with the raw tag under it, the value on the trailing side; VoiceOver reads "label, tag, value".
private struct MetadataRow: View {
    let entry: MetadataEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.panelGap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.label)
                Text(verbatim: entry.tag)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.labelSecondary)
            }
            Spacer(minLength: Theme.panelGap)
            Text(verbatim: entry.value)
                .multilineTextAlignment(.trailing)
                .lineLimit(6)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}
