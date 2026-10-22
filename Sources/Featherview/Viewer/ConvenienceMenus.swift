import FeatherviewCore
import SwiftUI

/// View › Sort By: a setting, so it works without a window; every open window re-sorts (ViewerView).
struct SortMenu: View {
    @AppStorage(AppSettings.sortKey.key) private var sortKey = AppSettings.sortKey.defaultValue
    @AppStorage(AppSettings.sortAscending.key) private var sortAscending = AppSettings.sortAscending.defaultValue

    var body: some View {
        Menu("Sort By") {
            Picker("Sort By", selection: $sortKey) {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Text(Self.title(key)).tag(key.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Picker("Direction", selection: $sortAscending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private static func title(_ key: SortKey) -> LocalizedStringKey {
        switch key {
        case .name: "Name"
        case .dateModified: "Date Modified"
        case .dateTaken: "Date Taken"
        case .size: "Size"
        case .kind: "Kind"
        }
    }
}

/// File › Open Recent: the system's recent files and folders, newest first (plan M11 Decision 1).
struct RecentMenu: View {
    private let recents = RecentFiles.shared

    var body: some View {
        Menu("Open Recent") {
            let urls = recents.urls
            let names = urls.map(\.lastPathComponent)
            ForEach(urls, id: \.self) { url in
                let name = url.lastPathComponent
                let folder = url.deletingLastPathComponent().lastPathComponent
                Button {
                    ViewerModel.lastActive.current.open(url)
                } label: {
                    Text(verbatim: names.filter { $0 == name }.count > 1 ? "\(name) — \(folder)" : name)
                }
            }
            Divider()
            Button("Clear Menu") { recents.clear() }
                .disabled(urls.isEmpty)
        }
    }
}

/// File › Share: the system's share menu for the current file.
struct ShareMenu: View {
    let model: ViewerModel?

    var body: some View {
        if let model, model.availability.canChangeFile, let url = model.list.current {
            ShareLink("Share", item: url)
        } else {
            Menu("Share") {}.disabled(true)
        }
    }
}
