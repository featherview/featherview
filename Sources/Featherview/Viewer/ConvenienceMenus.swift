import SwiftUI

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
