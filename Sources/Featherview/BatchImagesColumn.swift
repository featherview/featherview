import AppKit
import FeatherviewCore
import SwiftUI

/// The batch window's first column: the input list with thumbnails, adds, drop, sort and the list menu.
struct BatchImagesColumn: View {
    @Bindable var model: BatchModel
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $model.selection) {
                ForEach(model.inputs.items, id: \.self) { input in
                    BatchImageRow(input: input, state: model.state(of: input))
                }
            }
            .onDeleteCommand { if !model.isRunning { model.removeSelected() } }
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.isRunning else { return false }
                model.add(dropped: urls)
                return true
            } isTargeted: { isDropTarget = $0 }
            .overlay {
                if isDropTarget { RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2).padding(2) }
            }
            Divider()
            bottomBar
                .disabled(model.isRunning)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Images").font(.headline)
            Spacer()
            if model.scans > 0 { ProgressView().controlSize(.small) }
            Text(countLine)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var countLine: String {
        let count = model.inputs.items.count
        guard let bytes = model.totalBytes else { return String(localized: "\(count) files") }
        return String(localized: "\(count) files · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Add Files…") { model.addFilesPanel() }
                Button("Add Folder…") { model.addFolderPanel(subfolders: false) }
                Button("Add Folder with Subfolders…") { model.addFolderPanel(subfolders: true) }
                Divider()
                Button("Use Viewer's Folder") { model.useViewersFolder() }
                    .disabled(ViewerModel.lastActive.current.list.isEmpty)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add")
            Button { model.removeSelected() } label: { Image(systemName: "minus") }
                .accessibilityLabel("Remove")
                .disabled(model.selection.isEmpty)
            Menu("Sort") {
                Button("By Name") { model.sortByName() }
            }
            .fixedSize()
            Spacer()
            Menu {
                Button("Move Up") { model.moveSelected(by: -1) }
                    .disabled(model.selection.isEmpty)
                Button("Move Down") { model.moveSelected(by: 1) }
                    .disabled(model.selection.isEmpty)
                Divider()
                Button("Clear") { model.removeAll() }
                    .disabled(model.inputs.items.isEmpty)
                Divider()
                Button("Save List…") { model.saveListPanel() }
                    .disabled(model.inputs.items.isEmpty)
                Button("Load List…") { model.loadListPanel() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// Thumbnail and size line of a file, read once and kept for the most recently shown rows.
private final class RowInfo {
    let thumbnail: NSImage?
    let line: String
    init(thumbnail: NSImage?, line: String) { self.thumbnail = thumbnail; self.line = line }
}

/// About 20 KB per 72-px thumbnail: 500 rows keep memory bounded however long the list is.
@MainActor private let rowInfoCache: NSCache<NSURL, RowInfo> = {
    let cache = NSCache<NSURL, RowInfo>()
    cache.countLimit = 500
    return cache
}()

private struct BatchImageRow: View {
    let input: BatchInput
    let state: BatchRowState?
    @State private var info: RowInfo?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail = info?.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(input.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(stateLine ?? info?.line ?? " ")
                    .font(.caption)
                    .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            stateIcon
        }
        .task(id: input.url) { await load() }
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    private var stateLine: String? {
        switch state {
        case .done(let name): String(localized: "→ \(name)")
        case .failed(let line): line
        default: nil
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch state {
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary).accessibilityLabel("Waiting")
        case .working: ProgressView().controlSize(.small).accessibilityLabel("Working")
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
        case nil: EmptyView()
        }
    }

    private func load() async {
        let key = input.url as NSURL
        if let cached = rowInfoCache.object(forKey: key) { info = cached; return }
        // A row scrolled past quickly is cancelled here and never decodes.
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        let url = input.url
        let read = await Task.detached(priority: .utility) { () -> (CGImage?, String) in
            let image = try? ImageDecoder.decode(url, maxPixelSize: 72)
            let size = ImageDecoder.displaySize(of: url)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let pages = ImageFormats.mayHavePages(url) ? ImageDecoder.pageCount(of: url) : 1
            let byteText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let line: String
            switch (size, pages > 1) {
            case (let size?, false): line = String(localized: "\(Int(size.width)) × \(Int(size.height)) · \(byteText)")
            case (let size?, true):
                line = String(localized: "\(Int(size.width)) × \(Int(size.height)) · \(byteText) · \(pages) pages")
            case (nil, _): line = byteText
            }
            return (image, line)
        }.value
        let thumbnail = read.0.map { NSImage(cgImage: $0, size: .zero) }
        let loaded = RowInfo(thumbnail: thumbnail, line: read.1)
        rowInfoCache.setObject(loaded, forKey: key)
        info = loaded
    }
}
