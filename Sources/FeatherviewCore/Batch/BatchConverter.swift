import CoreGraphics
import CoreImage
import Foundation

public enum BatchConverter {
    /// One file's work before its commit.
    struct Prepared: Sendable {
        /// The encoded output; nil in rename mode (the input's bytes are copied at commit).
        var data: Data?
        /// For `{date}` in the rename pattern.
        var date: Date?
        /// "page 1 of 3".
        var note: String?
        var error: String?
        /// Trashed with the input; found here, in parallel, so the serial commit never lists a folder.
        var sidecars: [URL]

        init(data: Data? = nil, date: Date? = nil, note: String? = nil, error: String? = nil, sidecars: [URL] = []) {
            self.data = data; self.date = date; self.note = note; self.error = error; self.sidecars = sidecars
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
            if settings.mode != .rename, settings.watermark.isOn {
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

    /// Blocking ImageIO work runs on GCD, so it never ties up the cooperative pool the viewer's
    /// decode tasks need. The task group still caps how many run at once.
    private static func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: work()) }
        }
    }

    /// Decode (all pages the format needs), the pipeline per page, encode. Rename mode only reads the date.
    static func prepare(_ input: BatchInput, index: Int, settings: BatchSettings,
                        watermark: Result<CIImage?, WatermarkError>) -> Prepared {
        let url = input.url, name = url.lastPathComponent
        let usesDate = (settings.mode != .convert && settings.renamePattern.contains("{date}"))
            || (settings.mode != .rename && settings.text.isOn && settings.text.text.contains("{date}"))
        let date = usesDate ? MetadataReader.dateTaken(of: url) : nil
        if settings.mode == .rename {
            // The commit copies the bytes; a dangling link or a folder would copy as a link or fail as "Can't save".
            var isFolder: ObjCBool = false
            let target = url.resolvingSymlinksInPath().path
            guard FileManager.default.fileExists(atPath: target, isDirectory: &isFolder), !isFolder.boolValue,
                  FileManager.default.isReadableFile(atPath: target)
            else { return Prepared(error: String(localized: "Can't open \(name)")) }
            return Prepared(date: date)
        }

        let watermarkImage: CIImage?
        switch watermark {
        case .success(let image): watermarkImage = image
        case .failure(.unreadable(let file)):
            return Prepared(error: String(localized: "Can't read the watermark image \(file)"))
        }
        let format = settings.format, options = settings.options
        var limit: Int?, originalSize: CGSize?
        if settings.hasOperations, let size = ImageDecoder.displaySize(of: url),
           let l = ResizeStep.decodeLimit(settings, originalSize: size) {
            limit = l
            originalSize = size
        }
        // HDR is kept only for HEIC and AVIF (spec "Formats"), and reducing colours is 8-bit.
        let wantsHDR = ImageDecoder.supportsHDR && ["heic", "avif"].contains(format.id)
            && !(settings.colour.isOn && settings.colour.reduceColours != nil)
        var pages: [CGImage]
        do {
            // HEIC and AVIF write one page.
            pages = wantsHDR ? [try ImageDecoder.decode(url, maxPixelSize: limit, hdr: true)]
                : try ImageSaver.pages(of: url, for: format, options: options, maxPixelSize: limit)
        } catch { return Prepared(error: String(localized: "Can't open \(name)")) }
        let hdr = wantsHDR && ImageDecoder.isHDR(pages[0].colorSpace,
                                                 type: CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(CGImageSourceGetType))

        if settings.hasOperations {
            // The same day format as the rename pattern's {date}.
            let day = date.map { RenamePattern("{date}").baseName(original: "", index: 1, date: $0) } ?? ""
            let values = TextValues(name: url.deletingPathExtension().lastPathComponent,
                                    folder: url.deletingLastPathComponent().lastPathComponent, date: day, index: index + 1)
            do {
                pages = try pages.enumerated().map { page, image in
                    // Only page 1's original size is known; other pages resize from their decoded size.
                    let context = PipelineContext(values: values, originalSize: page == 0 ? originalSize : nil,
                                                  watermark: watermarkImage)
                    return try ImagePipeline.apply(image, settings, context: context, hdr: hdr)
                }
            } catch CanvasError.nothingLeft {
                return Prepared(error: String(localized: "\(name): the canvas settings leave no image"))
            } catch {
                return Prepared(error: String(localized: "Can't write \(name) as \(format.name)"))
            }
        }
        let dpi = settings.resize.isOn ? settings.resize.dpi : nil
        let data: Data
        do { data = try ImageEncoder.encode(pages, as: format, options: options, metadataFrom: url, dpi: dpi, hdr: hdr) }
        catch { return Prepared(error: String(localized: "Can't write \(name) as \(format.name)")) }
        let count = pages.count == 1 ? ImageDecoder.pageCount(of: url) : 1
        let note = count > 1 ? String(localized: "page 1 of \(count)", comment: "Batch log note: only the first page of a multi-page file was converted") : nil
        return Prepared(data: data, date: date, note: note)
    }

    /// Names, writes and finishes one file, in list order: the counter only advances for files that succeeded.
    static func commit(_ prepared: Prepared, input: BatchInput, settings: BatchSettings,
                       namer: inout BatchNamer, trash: (URL) throws -> Void) -> BatchResult {
        let url = input.url
        func failed(_ message: String) -> BatchResult { BatchResult(input: url, output: nil, status: .failed, message: message) }
        if let error = prepared.error { return failed(error) }
        let cantSave = String(localized: "Can't save \(url.lastPathComponent)")
        let unnamed = namer
        let planned = namer.next(for: input, date: prepared.date)
        let output: URL
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: planned.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The namer never returns an input or a folder; with "Replace existing files" it may return an existing file.
            if settings.safety.replaceExisting, let attributes = try? fm.attributesOfItem(atPath: planned.path),
               attributes[.type] as? FileAttributeType != .typeDirectory {
                try trash(planned)
            }
            output = try prepared.data.map { try write($0, to: planned) } ?? BatchCopy.copy(url, to: planned)
        } catch {
            namer = unnamed  // the name (and its number) goes to the next file that succeeds
            return failed(cantSave)
        }
        if settings.safety.keepDates,
           let date = (try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path))?[.modificationDate] as? Date {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: output.path)
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
        return BatchResult(input: url, output: output, status: .converted, message: message)
    }

    /// Writes a hidden temp file, then moves it in without replacing: a kill mid-write never leaves a
    /// partial file under the real name, and a file that appeared there is never touched (" 2" appended).
    static func write(_ data: Data, to output: URL) throws -> URL {
        let temp = output.deletingLastPathComponent().appendingPathComponent(".featherview-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        try data.write(to: temp)
        let base = output.deletingPathExtension().lastPathComponent
        var target = output
        for counter in 2...10_000 {
            let err = moveExclusive(temp.path, target.path)
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
