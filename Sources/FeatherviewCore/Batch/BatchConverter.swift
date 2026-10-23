import CoreGraphics
import CoreImage
import Foundation
import UniformTypeIdentifiers

public enum BatchConverter {
    /// One file's work before its commit.
    struct Prepared: Sendable {
        /// The encoded output; nil when the input's bytes are copied at commit or it has `parts`.
        var data: Data?
        /// An input with several outputs: each already written to a hidden temp file in its output folder,
        /// with its `{part}` label, so only one part is in memory at a time.
        var parts: [(file: URL, label: String)]
        /// For `{date}` in the rename pattern.
        var date: Date?
        /// The Date Taken step's new date ("yyyy:MM:dd HH:mm:ss") and the input's EXIF offset: the outputs' file dates.
        var dateTaken: String?
        var offset: String?
        /// "page 1 of 3".
        var note: String?
        var error: String?
        /// Trashed with the input; found here, in parallel, so the serial commit never lists a folder.
        var sidecars: [URL]

        init(data: Data? = nil, parts: [(file: URL, label: String)] = [], date: Date? = nil, dateTaken: String? = nil,
             offset: String? = nil, note: String? = nil, error: String? = nil, sidecars: [URL] = []) {
            self.data = data; self.parts = parts; self.date = date; self.dateTaken = dateTaken; self.offset = offset
            self.note = note; self.error = error; self.sidecars = sidecars
        }
    }

    /// All cores but one (spec "Running").
    public static let defaultWorkers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

    /// Calls `onResult` once per input, in list order, as each is committed (off the main thread).
    /// Returns every result (not-started ones after a Stop).
    public static func run(_ job: BatchJob, control: BatchControl = BatchControl(),
                           onResult: @escaping @Sendable (BatchResult) -> Void = { _ in }) async -> [BatchResult] {
        await run(job, control: control, workers: defaultWorkers, onResult: onResult, prepare: nil)
    }

    /// `trash` and `prepare` are seams for tests; `prepare` defaults to the real decode, pipeline and encode.
    static func run(
        _ job: BatchJob, control: BatchControl = BatchControl(), workers: Int = defaultWorkers,
        trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        moveSidecars: Bool = AppSettings.moveSidecars.value(),
        onResult: @escaping @Sendable (BatchResult) -> Void = { _ in },
        prepare: (@Sendable (Int, BatchInput) -> Prepared)? = nil
    ) async -> [BatchResult] {
        let settings = job.settings, inputs = job.inputs, total = inputs.count
        let prepare = prepare ?? {
            // Loaded once per batch; when it can't be read every file fails with that sentence.
            let watermark: Result<CIImage?, WatermarkError>
            if settings.watermark.isOn {
                do { watermark = .success(try WatermarkStep.load(settings.watermark.path)) }
                catch let error as WatermarkError { watermark = .failure(error) }
                catch { watermark = .failure(.unreadable(settings.watermark.path)) }
            } else {
                watermark = .success(nil)
            }
            return { index, input in Self.prepare(input, index: index, settings: settings, watermark: watermark) }
        }()
        let sidecars = settings.safety.trashOriginals && moveSidecars ? Sidecars.Finder() : nil
        var namer = BatchNamer(settings: settings, inputs: inputs)
        var results = [BatchResult?](repeating: nil, count: total)
        var waiting: [Int: Prepared] = [:]
        var started = 0, inFlight = 0, nextCommit = 0
        await withTaskGroup(of: (Int, Prepared).self) { group in
            while true {
                // Ahead of the commit by at most 2 × workers files, so finished outputs can't pile up in memory.
                while started < total, inFlight < workers, started - nextCommit < 2 * workers,
                      !control.isPaused, !control.isStopped {
                    let index = started
                    group.addTask {
                        (index, await offPool {
                            var prepared = prepare(index, inputs[index])
                            if let sidecars, prepared.error == nil { prepared.sidecars = sidecars.files(for: inputs[index].url) }
                            return prepared
                        })
                    }
                    started += 1
                    inFlight += 1
                }
                if inFlight == 0 {
                    if started == total || control.isStopped { break }
                    await control.waitWhilePaused()
                    continue
                }
                guard let (index, prepared) = await group.next() else { break }
                inFlight -= 1
                waiting[index] = prepared
                while let next = waiting.removeValue(forKey: nextCommit) {
                    let input = inputs[nextCommit]
                    // Off the pool too: commits write and copy whole files. Awaited one at a time, so order holds.
                    let (result, named) = await offPool { [namer] in
                        var namer = namer
                        let result = commit(next, input: input, settings: settings, namer: &namer, trash: trash)
                        return (result, namer)
                    }
                    namer = named
                    results[nextCommit] = result
                    onResult(result)
                    nextCommit += 1
                }
            }
        }
        for index in nextCommit..<total {
            let result = BatchResult(input: inputs[index].url, output: nil, status: .notStarted, message: nil)
            results[index] = result
            onResult(result)
        }
        PipelineRender.releaseBuffers()
        return results.compactMap { $0 }
    }

    /// Decode (all pages the format needs, or each frame or page as its own output), the pipeline per
    /// page, tiles, encode. A copy only reads the date, or rewrites it losslessly.
    static func prepare(_ input: BatchInput, index: Int, settings: BatchSettings,
                        watermark: Result<CIImage?, WatermarkError>) -> Prepared {
        let url = input.url, name = url.lastPathComponent
        // Each read once per input, and only when a step needs it.
        lazy var source = CGImageSourceCreateWithURL(url as CFURL, nil)
        lazy var pageCount = ImageDecoder.pageCount(of: url, source: source)
        lazy var animation = Animation.read(url)
        var newDate: String?, offset: String?
        if settings.dateTaken.isOn {
            newDate = settings.dateTaken.newDate(for: url)
            guard newDate != nil else {
                return Prepared(error: settings.dateTaken.mode == .set
                    ? String(localized: "Choose a date for the Date Taken step")
                    : String(localized: "Can't change the date taken of \(name)"))
            }
            offset = source.flatMap { DateTaken.exifValue($0, kCGImagePropertyExifOffsetTimeOriginal) }
        }
        let usesDate = settings.renamePattern.contains("{date}") || (settings.text.isOn && settings.text.text.contains("{date}"))
        let date = newDate.flatMap(MetadataReader.exifDate) ?? (usesDate ? MetadataReader.dateTaken(of: url) : nil)
        // With Frames and Pages, a still (one output) is copied as it would be without the step.
        let copies = settings.copiesUnchanged
            || (!settings.changeFormat && !settings.hasOperations && settings.frames.isOn && !settings.tiles.isOn
                && animation == nil && pageCount <= 1)
        if copies {
            // The commit copies the bytes; a dangling link or a folder would copy as a link or fail as "Can't save".
            var isFolder: ObjCBool = false
            let target = url.resolvingSymlinksInPath().path
            guard FileManager.default.fileExists(atPath: target, isDirectory: &isFolder), !isFolder.boolValue,
                  FileManager.default.isReadableFile(atPath: target)
            else { return Prepared(error: String(localized: "Can't open \(name)")) }
            guard settings.dateTaken.isOn else { return Prepared(date: date) }
            guard let newDate, let data = try? DateTaken.rewritten(url, date: newDate)
            else { return Prepared(error: String(localized: "Can't change the date taken of \(name)")) }
            return Prepared(data: data, date: date, dateTaken: newDate, offset: offset)
        }

        let watermarkImage: CIImage?
        switch watermark {
        case .success(let image): watermarkImage = image
        case .failure(.unreadable(let file)):
            return Prepared(error: String(localized: "Can't read the watermark image \(file)"))
        }
        let format: OutputFormat, options: FormatOptions
        if settings.changeFormat {
            format = settings.format
            options = settings.options
        } else {
            // Its own format, by extension first (.pbm, .pgm and .ppm share one UTType), then by type
            // (.jpeg, .tif): a CR3 that ImageIO reads still fails.
            var ext = url.pathExtension.lowercased()
            ext = ["jfif": "jpg", "jif": "jpg", "jfi": "jpg", "heif": "heic", "hif": "heic", "apng": "png"][ext] ?? ext
            let type = UTType(filenameExtension: ext)
            guard let own = FormatRegistry.format(id: ext) ?? FormatRegistry.writable.first(where: { type != nil && $0.type == type }),
                  // With Frames and Pages each output is one page.
                  own.writer == .pdf || own.optionFields.contains(.keepAllPages) || settings.frames.isOn
                    || pageCount <= 1
            else { return Prepared(error: String(localized: "Can't save \(name) in its own format")) }
            format = own
            options = FormatSettings.options(for: own)
        }
        var limit: Int?, originalSize: CGSize?
        if settings.hasOperations, let size = ImageDecoder.displaySize(of: url, source: source),
           let l = ResizeStep.decodeLimit(settings, originalSize: size) {
            limit = l
            originalSize = size
        }
        // Frames and Pages: every frame of an animation (from one kept source) or every page is its own output.
        var reader: FrameReader?, units = 1
        if settings.frames.isOn {
            if let animation {
                do { reader = try FrameReader(url: url, target: .full, colorSpace: nil) }
                catch { return Prepared(error: String(localized: "Can't open \(name)")) }
                units = animation.frameCount
            } else if pageCount > 1 {
                units = pageCount
            }
        }
        // HDR is kept only for HEIC and AVIF (spec "Formats"), for one decode per input, and reducing colours is 8-bit.
        let wantsHDR = units == 1 && ImageDecoder.supportsHDR && ["heic", "avif"].contains(format.id)
            && !(settings.colour.isOn && settings.colour.reduceColours != nil)
        let tiles = settings.tiles
        let labels = PartLabels.combined(frames: units, rows: tiles.isOn ? tiles.rows : 1, columns: tiles.isOn ? tiles.columns : 1)
        let folder = BatchNamer.folder(for: input, settings: settings)
        let values = TextValues(url: url, date: date, index: index + 1)
        let dpi = settings.resize.isOn ? settings.resize.dpi : nil
        var single: Data?, parts: [(file: URL, label: String)] = [], note: String?
        func failed(_ message: String) -> Prepared {
            for part in parts { try? FileManager.default.removeItem(at: part.file) }
            return Prepared(error: message)
        }
        for unit in 0..<units {
            var pages: [CGImage]
            do {
                if let reader {
                    pages = [try reader.frame(unit)]
                } else if units > 1 {
                    pages = [try ImageDecoder.decode(url, maxPixelSize: limit, page: unit)]
                } else if wantsHDR {  // HEIC and AVIF write one page
                    pages = [try ImageDecoder.decode(url, maxPixelSize: limit, hdr: true)]
                } else if tiles.isOn {  // tiles of page 1 only
                    pages = [try ImageDecoder.decode(url, maxPixelSize: limit)]
                } else {
                    pages = try ImageSaver.pages(of: url, for: format, options: options, maxPixelSize: limit, pageCount: pageCount)
                }
            } catch { return failed(String(localized: "Can't open \(name)")) }
            let hdr = wantsHDR && ImageDecoder.isHDR(pages[0].colorSpace,
                                                     type: source.flatMap(CGImageSourceGetType))
            if units == 1, pages.count == 1, pageCount > 1 {
                note = String(localized: "page 1 of \(pageCount)", comment: "Batch log note: only the first page of a multi-page file was converted")
            }

            if settings.hasOperations {
                do {
                    pages = try pages.enumerated().map { page, image in
                        // Only page 1's original size is known; other pages resize from their decoded size.
                        let context = PipelineContext(values: values, originalSize: unit == 0 && page == 0 ? originalSize : nil,
                                                      watermark: watermarkImage)
                        return try ImagePipeline.apply(image, settings, context: context, hdr: hdr)
                    }
                } catch CanvasError.nothingLeft {
                    return failed(String(localized: "\(name): the canvas settings leave no image"))
                } catch {
                    return failed(String(localized: "Can't write \(name) as \(format.name)"))
                }
            }
            var outputs = [pages]
            if tiles.isOn {
                do { outputs = try TileStep.cut(pages[0], columns: tiles.columns, rows: tiles.rows, overlap: tiles.overlap).map { [$0] } }
                catch { return failed(String(localized: "\(name): the tile settings leave no image")) }
            }
            for output in outputs {
                let data: Data
                do {
                    data = try ImageEncoder.encode(output, as: format, options: options, metadataFrom: url, dpi: dpi, hdr: hdr,
                                                   dateTaken: newDate)
                } catch { return failed(String(localized: "Can't write \(name) as \(format.name)")) }
                guard !labels.isEmpty else { single = data; continue }
                // On disk as soon as it is made, so a 500-frame GIF holds one frame in memory.
                let temp = ImageSaver.tempURL(in: folder)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: temp)
                } catch {
                    try? FileManager.default.removeItem(at: temp)
                    return failed(String(localized: "Can't save \(name)"))
                }
                parts.append((temp, labels[parts.count]))
            }
        }
        return Prepared(data: single, parts: parts, date: date, dateTaken: newDate, offset: offset, note: note)
    }

    /// Names, writes and finishes one file, in list order: the counter only advances for files that succeeded.
    /// An input with parts is one unit: if one part can't be moved in, the parts moved before it are removed.
    /// `move` is a seam for tests.
    static func commit(_ prepared: Prepared, input: BatchInput, settings: BatchSettings,
                       namer: inout BatchNamer, trash: (URL) throws -> Void,
                       move: (String, String) -> Int32 = { moveExclusive($0, $1) }) -> BatchResult {
        let url = input.url, fm = FileManager.default
        func failed(_ message: String) -> BatchResult { BatchResult(input: url, output: nil, status: .failed, message: message) }
        if let error = prepared.error { return failed(error) }
        let cantSave = String(localized: "Can't save \(url.lastPathComponent)")
        let unnamed = namer
        let planned = namer.names(for: input, date: prepared.date, parts: prepared.parts.map(\.label))
        var outputs: [URL] = []
        do {
            try fm.createDirectory(at: planned[0].deletingLastPathComponent(), withIntermediateDirectories: true)
            for (n, name) in planned.enumerated() {
                // The namer never returns an input or a folder; with "Replace existing files" it may return an existing file.
                if settings.safety.replaceExisting, let attributes = try? fm.attributesOfItem(atPath: name.path),
                   attributes[.type] as? FileAttributeType != .typeDirectory {
                    try trash(name)
                }
                if !prepared.parts.isEmpty {
                    outputs.append(try moveIn(prepared.parts[n].file, to: name, move: move))
                } else if let data = prepared.data {
                    outputs.append(try write(data, to: name, move: move))
                } else {
                    outputs.append(try BatchCopy.copy(url, to: name))
                }
            }
        } catch {
            // This run's own new files, and the temps not moved in yet.
            for file in outputs + prepared.parts.map(\.file) { try? fm.removeItem(at: file) }
            namer = unnamed  // the names (and their number) go to the next file that succeeds
            return failed(cantSave)
        }
        if let dateTaken = prepared.dateTaken {
            for output in outputs { DateTaken.setFileDates(output, date: dateTaken, offset: prepared.offset) }
        } else if settings.safety.keepDates,
           let date = url.modificationDate {
            for output in outputs { try? fm.setAttributes([.modificationDate: date], ofItemAtPath: output.path) }
        }
        var message = prepared.note
        if settings.safety.trashOriginals {
            do {
                try trash(url)
                // Another file of the same name left in the folder (an in-place output, the RAW of a RAW+JPEG
                // pair) still owns the sidecars. Listed only when there are sidecars to move.
                let stem = Sidecars.stem(of: url)
                let owned = !prepared.sidecars.isEmpty && Sidecars.list(url.deletingLastPathComponent()).contains {
                    Sidecars.stem(of: $0) == stem && !Sidecars.extensions.contains($0.pathExtension.lowercased())
                }
                if !owned { for sidecar in prepared.sidecars { try? trash(sidecar) } }
            } catch {
                let kept = String(localized: "Can't move \(url.lastPathComponent) to the Trash")
                message = message.map { String(localized: "\($0); \(kept)") } ?? kept
            }
        }
        return BatchResult(input: url, outputs: outputs, status: .converted, message: message)
    }

    /// Writes a hidden temp file, then moves it in without replacing: a kill mid-write never leaves a
    /// partial file under the real name, and a file that appeared there is never touched (" 2" appended).
    static func write(_ data: Data, to output: URL,
                      move: (String, String) -> Int32 = { moveExclusive($0, $1) }) throws -> URL {
        let temp = ImageSaver.tempURL(in: output.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: temp) }
        try data.write(to: temp)
        return try moveIn(temp, to: output, move: move)
    }

    /// Moves the temp file `temp` to `output` without replacing anything (" 2", " 3" when the name was taken meanwhile).
    static func moveIn(_ temp: URL, to output: URL, move: (String, String) -> Int32) throws -> URL {
        let base = output.deletingPathExtension().lastPathComponent
        var target = output
        for counter in 2...10_000 {
            let err = move(temp.path, target.path)
            if err == 0 { return target }
            guard err == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO) }
            target = BatchNamer.fitted(base, suffix: " \(counter)", ext: output.pathExtension,
                                       in: output.deletingLastPathComponent())
        }
        throw POSIXError(.EEXIST)
    }

    /// Moves `from` to `to` without replacing anything; returns 0 or an errno. `renameExcl` is a seam for tests.
    static func moveExclusive(
        _ from: String, _ to: String,
        renameExcl: (String, String) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno }
    ) -> Int32 {
        let err = renameExcl(from, to)
        guard err == ENOTSUP || err == EINVAL else { return err }
        // exFAT and some shares lack RENAME_EXCL (and hard links): claim the name with an exclusive
        // create, then rename over our own empty placeholder.
        let fd = open(to, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard fd >= 0 else { return errno }
        close(fd)
        if rename(from, to) == 0 { return 0 }
        let renameErr = errno
        unlink(to)
        return renameErr
    }
}
