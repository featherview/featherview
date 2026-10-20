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
            HStack(alignment: .top, spacing: 16) {
                pane(preview.original, caption: preview.originalSize.map { Text("Original \(Int($0.width)) × \(Int($0.height))") })
                if let error = preview.error {
                    Text(error)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pane(preview.output, caption: preview.outputSize.map { Text("Output \(Int($0.width)) × \(Int($0.height))") })
                }
                names
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let applied = BatchCard.appliedLine(model.settings) {
                Text(applied)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .onChange(of: imageKey, initial: true) { preview.updateImage(imageKey) }
        .onChange(of: namesKey, initial: true) { preview.updateNames(namesKey) }
    }

    private func pane(_ image: CGImage?, caption: Text?) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let caption {
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(preview.names.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !preview.names.isEmpty {
                Group {
                    if preview.more > 0 {
                        Text("… \(preview.more) more · into \(preview.folder)")
                    } else {
                        Text("Into \(preview.folder)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.top, 4)
            }
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
    private(set) var error: String?
    private(set) var names: [String] = []
    private(set) var more = 0
    private(set) var folder = ""

    /// The last small decode and watermark, so a settings change only reruns the pipeline.
    @ObservationIgnored private var cache = Cache()
    @ObservationIgnored private let imageJobs = LatestWins()
    @ObservationIgnored private let nameJobs = LatestWins()

    struct Cache: Sendable {
        var url: URL?
        var image: CGImage?
        var size: CGSize?
        var watermarkPath: String?
        var watermark: CIImage?
    }

    private struct Rendered: Sendable {
        var cache: Cache
        var output: CGImage?
        var outputSize: CGSize?
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
            error = result.error
        }
    }

    func updateNames(_ key: NamesKey) {
        nameJobs.submit { [self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { Self.names(key) }.value
            guard !Task.isCancelled else { return }
            (names, more, folder) = result
        }
    }

    /// The first five names as if every file succeeds, how many follow, and the first file's folder.
    private nonisolated static func names(_ key: NamesKey) -> ([String], Int, String) {
        guard let first = key.inputs.first else { return ([], 0, "") }
        let s = key.settings
        var namer = BatchNamer(settings: s, inputs: key.inputs)
        let usesDate = s.renamePattern.contains("{date}")
        let names = key.inputs.prefix(5).map {
            namer.next(for: $0, date: usesDate ? MetadataReader.dateTaken(of: $0.url) : nil).lastPathComponent
        }
        return (names, key.inputs.count - names.count, namer.folder(for: first).path)
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
            return Rendered(cache: cache, output: image, outputSize: size)
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
            return Rendered(cache: cache, output: output, outputSize: outputSize)
        } catch CanvasError.nothingLeft {
            return Rendered(cache: cache, error: String(localized: "The canvas settings leave no image"))
        } catch {
            return Rendered(cache: cache, error: String(localized: "Can't preview \(name)"))
        }
    }
}
