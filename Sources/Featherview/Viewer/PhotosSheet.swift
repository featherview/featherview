import FeatherviewCore
import FeatherviewPhotos
import Photos
import SwiftUI

/// File › Open from Photos… (⇧⌘O): the library's albums (spec "Photos library"). ↑/↓ and typing a name select,
/// Return or a double click opens, Esc closes. PhotoKit is first asked here, never at launch.
struct PhotosAlbumSheet: View {
    let model: ViewerModel
    /// nil while access is asked for and the albums are read.
    @State private var access: PHAuthorizationStatus?
    @State private var rows: [PhotosAlbumRow] = []
    @State private var counts: [String: Int] = [:]
    @State private var selection: String?
    /// Type-select: the letters typed so far, dropped after a pause.
    @State private var typed = ""
    @State private var typedAt = Date.distantPast

    private static let lastAlbumKey = "photosLastAlbum"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelGap) {
            Text("Open from Photos").font(Theme.panelTitle)
            if access == .denied || access == .restricted {
                denied
            } else {
                albums
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.showsPhotos = false }
                    .keyboardShortcut(.cancelAction)
                if access != .denied, access != .restricted {
                    Button("Open") { open(selection) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selection == nil)
                }
            }
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.chooserWidth)
        .task { await load() }
    }

    private var albums: some View {
        List(selection: $selection) {
            ForEach(Array(PhotosSheet.sections(rows).enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section.rows) { row($0) }
                } header: {
                    if let title = section.title { Text(verbatim: title) }
                }
            }
        }
        .frame(height: Theme.chooserListHeight)
        .contextMenu(forSelectionType: String.self, menu: { _ in }) { open($0.first) }
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.whitespaces), action: typeSelect)
    }

    private func row(_ row: PhotosAlbumRow) -> some View {
        HStack(spacing: Theme.rowGap) {
            VStack(alignment: .leading) {
                Text(verbatim: row.name).font(Theme.row).lineLimit(1)
                if let subtitle = PhotosSheet.subtitle(row) {
                    Text(verbatim: subtitle).font(Theme.hint).foregroundStyle(Theme.labelSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let count = counts[row.id] {
                Text(count, format: .number).font(Theme.rowValue).foregroundStyle(Theme.labelSecondary)
            }
        }
        .tag(row.id)
        // Rows are built as they scroll in: only visible albums are counted, off the main thread.
        .task(id: row.id) {
            guard counts[row.id] == nil else { return }
            counts[row.id] = await PhotosLibrary.shared.count(row.id)
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: Theme.panelGap) {
            Text(verbatim: PhotosText.denied).font(Theme.row)
            Text(verbatim: PhotosText.deniedHelp).font(Theme.row).foregroundStyle(Theme.labelSecondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func load() async {
        let status = await PhotosLibrary.shared.authorize()
        guard status == .authorized || status == .limited else { return access = status }
        let rows = await PhotosLibrary.shared.albums()
        self.rows = rows
        model.photosAlbums = rows
        let last = UserDefaults.standard.string(forKey: Self.lastAlbumKey)
        selection = rows.contains { $0.id == last } ? last : rows.first?.id
        access = status
    }

    private func open(_ album: String?) {
        guard let album else { return }
        UserDefaults.standard.set(album, forKey: Self.lastAlbumKey)
        model.showsPhotos = false
        model.openPhotos(album: album)
    }

    /// Selects the first album (in sheet order) whose name starts with what was typed; a pause starts anew.
    private func typeSelect(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        let now = Date.now
        typed = (now.timeIntervalSince(typedAt) > Theme.Motion.typeSelectPause ? "" : typed) + press.characters
        typedAt = now
        let ordered = PhotosSheet.sections(rows).flatMap(\.rows)
        if let match = ordered.first(where: { $0.name.localizedStandardRange(of: typed)?.lowerBound == $0.name.startIndex }) {
            selection = match.id
        }
        return .handled
    }
}
