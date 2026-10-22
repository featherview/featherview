import CoreImage
import FeatherviewCore
import SwiftUI

/// Under the cards (spec "Window"): the selected input (or the first) with every operation applied next
/// to the original, the first output names and the applied steps in order. Computed off the main thread, 150 ms
/// after the last change, the previous computation cancelled.
struct BatchPreview: View {
    let model: BatchModel
    @State private var preview = BatchPreviewModel()

    var body: some View {
        let items = model.inputs.items
        let index = items.firstIndex(where: model.selection.contains) ?? (items.isEmpty ? nil : 0)
        let imageKey = BatchPreviewModel.ImageKey(settings: model.settings, input: index.map { items[$0] }, index: index ?? 0)
        let namesKey = BatchPreviewModel.NamesKey(settings: model.settings, inputs: items)
        VStack(alignment: .leading, spacing: 6) {
            // Captions on one shared top line, each column's content under its caption.
            if !items.isEmpty {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        caption(preview.error == nil ? preview.originalSize.map { Text("Original \(Int($0.width)) × \(Int($0.height))") } : nil)
                        caption(preview.error == nil ? preview.partSize.map { size in
                            preview.parts > 1
                                ? Text("Output \(Int(size.width)) × \(Int(size.height)) · \(preview.parts) files",
                                       comment: "Batch preview: each output file's pixel size and how many files one input gives")
                                : Text("Output \(Int(size.width)) × \(Int(size.height))")
                        } : nil)
                        caption(nil)
                    }
                    GridRow {
                        if let error = preview.error {
                            // Nothing to compare: the reason takes both pictures' place.
                            Text(error)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .gridCellColumns(2)
                        } else {
                            picture(preview.original)
                            picture(preview.output, tiles: preview.tiles, in: preview.outputSize)
                        }
                        namesList
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            if let applied = BatchCard.appliedLine(model.settings) {
                Text(applied)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .onChange(of: imageKey, initial: true) { preview.updateImage(imageKey) }
        .onChange(of: namesKey, initial: true) { preview.updateNames(namesKey) }
    }

    private var names: [String] { preview.names }

    private func caption(_ text: Text?) -> some View {
        (text ?? Text(verbatim: " "))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `tiles` in the pixels of `size`, drawn as lines over the picture.
    private func picture(_ image: CGImage?, tiles: [CGRect] = [], in size: CGSize? = nil) -> some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        if let size, !tiles.isEmpty {
                            GeometryReader { shown in
                                let scale = shown.size.width / size.width
                                Path { path in
                                    for tile in tiles {
                                        path.addRect(tile.applying(CGAffineTransform(scaleX: scale, y: scale)))
                                    }
                                }
                                .stroke(Theme.accent, lineWidth: 1)
                            }
                        }
                    }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var namesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !names.isEmpty {
                Group {
                    if preview.more > 0 {
                        Text("… \(preview.more) more · into \(preview.folder)")
                    } else {
                        Text("Into \(preview.folder)")
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.top, 4)
            }
        }
    }
}

/// The running view's picture (design "Running"): the image written last, decoded off the main thread to fit
/// the area, with its name, pixel size and file size. Results arrive about four times a second; a newer
/// file cancels the decode still waiting.
struct BatchWrittenPreview: View {
    let url: URL?
    @State private var shown: Shown?
    @State private var jobs = LatestWins()
    @Environment(\.displayScale) private var displayScale

    struct Shown: Sendable {
        var url: URL
        var image: CGImage?
        var size: CGSize?
        var bytes: Int?
    }

    var body: some View {
        VStack(spacing: Theme.messagePadding) {
            // Measures the image area only, not the caption row.
            GeometryReader { geometry in
                Group {
                    if let image = shown?.image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: url, initial: true) {
                    load(area: PixelSize(width: max(Int((geometry.size.width * displayScale).rounded(.up)), 1),
                                         height: max(Int((geometry.size.height * displayScale).rounded(.up)), 1)))
                }
            }
            if let shown {
                caption(shown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func caption(_ shown: Shown) -> Text {
        let name = shown.url.lastPathComponent
        guard let size = shown.size else { return Text(verbatim: name) }
        let bytes = Int64(shown.bytes ?? 0).formatted(.byteCount(style: .file))
        return Text("\(name) · \(Int(size.width)) × \(Int(size.height)) · \(bytes)",
                    comment: "Batch running preview: file name, pixel size, file size")
    }

    private func load(area: PixelSize) {
        guard let url else { return shown = nil }
        jobs.submit {
            let loaded = await Task.detached(priority: .userInitiated) {
                Shown(url: url, image: try? ImageDecoder.decode(url, halvingSteps: true, fitting: [area]),
                      size: ImageDecoder.displaySize(of: url),
                      bytes: try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            }.value
            guard !Task.isCancelled else { return }
            shown = loaded
        }
    }
}

@MainActor @Observable
final class BatchPreviewModel {
    struct ImageKey: Equatable, Sendable {
        var settings: BatchSettings
        var input: BatchInput?
        /// The input's place in the list, for the text's `{n}`.
        var index: Int
    }

    struct NamesKey: Equatable, Sendable {
        var settings: BatchSettings
        var inputs: [BatchInput]
    }

    private(set) var original: CGImage?
    private(set) var output: CGImage?
    private(set) var originalSize: CGSize?
    private(set) var outputSize: CGSize?
    /// How many files the shown input gives, and its tiles in the pixels of `outputSize` (empty without Tiles).
    private(set) var parts = 1
    private(set) var tiles: [CGRect] = []
    private(set) var error: String?

    /// The size of each output file: a tile's, else the whole output's.
    var partSize: CGSize? { tiles.first?.size ?? outputSize }
    private(set) var names: [String] = []
    private(set) var more = 0
    private(set) var folder = ""

    /// The last small decode and watermark, so a settings change only reruns the pipeline.
    @ObservationIgnored private var cache = Cache()
    /// Frames or pages per file, for the names: they don't change with the settings.
    @ObservationIgnored private var frameCounts: [URL: Int] = [:]
    @ObservationIgnored private let imageJobs = LatestWins()
    @ObservationIgnored private let nameJobs = LatestWins()

    struct Cache: Sendable {
        var url: URL?
        var image: CGImage?
        var size: CGSize?
        var watermarkPath: String?
        var watermark: CIImage?
        var frames: Int?
    }

    private struct Rendered: Sendable {
        var cache: Cache
        var output: CGImage?
        var outputSize: CGSize?
        var parts = 1
        var tiles: [CGRect] = []
        var error: String?
    }

    func updateImage(_ key: ImageKey) {
        imageJobs.submit { [self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let cache = self.cache
            let result = await Task.detached(priority: .userInitiated) { Self.render(key, cache: cache) }.value
            self.cache = result.cache
            guard !Task.isCancelled else { return }
            original = result.cache.image
            originalSize = result.cache.size
            output = result.output
            outputSize = result.outputSize
            parts = result.parts
            tiles = result.tiles
            error = result.error
        }
    }

    func updateNames(_ key: NamesKey) {
        nameJobs.submit { [self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let counts = frameCounts
            let job = Task.detached(priority: .userInitiated) {
                BatchPreviewNames.compute(key.settings, inputs: key.inputs, frameCounts: counts)
            }
            let result = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            frameCounts = result.frameCounts
            guard !Task.isCancelled, !result.cancelled else { return }
            (names, more, folder) = (result.names, result.more, result.folder)
        }
    }

    /// The shown input's file count and, with Tiles, its tiles of the output.
    private nonisolated static func split(_ rendered: Rendered, _ s: BatchSettings, url: URL) -> Rendered {
        var rendered = rendered
        guard s.splits, let size = rendered.outputSize else { return rendered }
        if s.frames.isOn && rendered.cache.frames == nil { rendered.cache.frames = BatchPreviewNames.frames(of: url) }
        rendered.parts = max(BatchPreviewNames.labels(s, frames: s.frames.isOn ? rendered.cache.frames ?? 1 : 1).count, 1)
        guard s.tiles.isOn else { return rendered }
        do {
            rendered.tiles = try TileStep.rects(width: Int(size.width), height: Int(size.height),
                                                columns: s.tiles.columns, rows: s.tiles.rows, overlap: s.tiles.overlap)
        } catch {
            return Rendered(cache: rendered.cache, error: String(localized: "The tile settings leave no image"))
        }
        return rendered
    }

    private nonisolated static func render(_ key: ImageKey, cache: Cache) -> Rendered {
        var cache = cache
        guard let input = key.input else { return Rendered(cache: Cache()) }
        let url = input.url, name = url.lastPathComponent
        if cache.url != url {
            cache = Cache(url: url, watermarkPath: cache.watermarkPath, watermark: cache.watermark)
            cache.size = ImageDecoder.displaySize(of: url)
            cache.image = try? ImageDecoder.decode(url, maxPixelSize: 400)
        }
        guard let image = cache.image, let size = cache.size else {
            return Rendered(cache: cache, error: String(localized: "Can't open \(name)"))
        }
        let s = key.settings
        guard s.hasOperations else {
            return split(Rendered(cache: cache, output: image, outputSize: size), s, url: url)
        }
        var watermark: CIImage?
        if s.watermark.isOn {
            if cache.watermarkPath != s.watermark.path {
                cache.watermarkPath = s.watermark.path
                cache.watermark = try? WatermarkStep.load(s.watermark.path)
            }
            guard let loaded = cache.watermark else {
                let file = (s.watermark.path as NSString).lastPathComponent
                return Rendered(cache: cache, error: s.watermark.path.isEmpty
                    ? String(localized: "Choose a watermark image")
                    : String(localized: "Can't read the watermark image \(file)"))
            }
            watermark = loaded
        }
        // Same values as the converter, so the preview shows the text the output gets.
        let date = s.text.isOn && s.text.text.contains("{date}") ? MetadataReader.dateTaken(of: url) : nil
        let day = date.map { RenamePattern("{date}").baseName(original: "", index: 1, date: $0) } ?? ""
        let values = TextValues(name: url.deletingPathExtension().lastPathComponent,
                                folder: url.deletingLastPathComponent().lastPathComponent, date: day, index: key.index + 1)
        do {
            let (output, outputSize) = try ImagePipeline.preview(image, originalSize: size, s,
                                                                 context: PipelineContext(values: values, watermark: watermark))
            return split(Rendered(cache: cache, output: output, outputSize: outputSize), s, url: url)
        } catch CanvasError.nothingLeft {
            return Rendered(cache: cache, error: String(localized: "The canvas settings leave no image"))
        } catch {
            return Rendered(cache: cache, error: String(localized: "Can't preview \(name)"))
        }
    }
}
