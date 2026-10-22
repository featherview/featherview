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
