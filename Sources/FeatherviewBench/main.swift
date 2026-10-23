import CoreGraphics
import FeatherviewCore
import Foundation

// featherview-bench: decode and browse timings through the viewer's own code paths, without a window.

let usage = """
    Usage (build with -c release, or the numbers mean little and 50 MP takes minutes):
      swift run -c release featherview-bench corpus <dir>
      swift run -c release featherview-bench decode <dir> [--raw <dir>] [--screen WxH ...] [--runs 10]
                                                    [--json out.json] [--baseline in.json]
      swift run -c release featherview-bench browse <dir>/browse [--interval-ms 300] [--screen WxH]
      swift run -c release featherview-bench thumbnail <file or dir> [--out <dir>]
      swift run -c release featherview-bench grid <dir> [--points 128] [--scale 2] [--cells 40] [--width N]
                                                  [--json out.json] [--baseline in.json]
      swift run -c release featherview-bench fuzz <seed dir or file> --out <dir> [--seconds 60] [--seed N]

    corpus  writes generated test images into <dir> (never commit them).
    decode  times the viewer's fit decode per file and screen, plus one full-size decode per file,
            and for 50 MP files the zoom decode at 0.25, 0.5 and 1.0 (rows "zoom <factor>").
            The first run reads the file from disk; for a truly cold first run, run `sudo purge`
            before (the bench never does). --baseline exits 1 if a median is > 10 % slower or a row is gone.
    browse  steps through the folder like a held arrow key: one step every --interval-ms, whether
            or not the last one finished, through an 8-image cache with 2 neighbours prefetched each way.
    thumbnail  asks Finder's thumbnail service (256 × 256 points at 2×) for each file, as Finder does, and
            exits 1 if one gets no thumbnail; --out also writes them as PNG. It doesn't say which extension
            drew a thumbnail: for formats only Featherview reads, any thumbnail at all is ours. macOS uses the
            copy of the app registered with the highest version (`pluginkit -m -v -p com.apple.quicklook.thumbnail`).
    grid    the grid's first screen: the first --cells files in Finder order, all asked at once as thumbnails
            (`ThumbnailSize.decodeSide` of --points at --scale) through one byte-budgeted cache and a
            --width-wide queue (default the app's: cores − 2, within 2…6). Prints the time until the last
            one is done, p50 / p95 per file and the cache's decoded bytes. Budgets: browse < 400 ms, grid-heic < 150 ms.
    fuzz    mutates each seed (one valid file per own format, `FEATHERVIEW_FUZZ_SEEDS=<dir> swift test --filter
            FuzzSeedTests` writes them) and runs it through the own decoder, until --seconds are up. Each input is
            written to <out>/current.<ext> first, so a crash leaves it behind; an input taking over 5 s is copied to
            <out>/hang-<n>.<ext> and exits 3. scripts/fuzz.sh runs it under AddressSanitizer, one format at a time.
    Screens are in pixels; default 3024x1964 3456x2234 5120x2880 (decode), 3024x1964 (browse).
    """

struct Screen: Codable, Hashable, CustomStringConvertible {
    let width: Int, height: Int
    var description: String { "\(width)x\(height)" }

    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ $0 > 0 }) else { return nil }
        (width, height) = (parts[0], parts[1])
    }
}

let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)

/// The screens as the viewer's fit decode takes them.
func pixelSizes(_ screens: [Screen]) -> [PixelSize] {
    screens.map { PixelSize(width: $0.width, height: $0.height) }
}

/// The viewer's fit decode, exactly as `ViewerModel` and `ImageCache` call it. Keep it the one place this call
/// lives: a change to the fit rule changes only this function, so before and after stay comparable.
func fitDecode(_ url: URL, screens: [Screen]) throws -> CGImage {
    try ImageDecoder.decode(url, halvingSteps: true, fitting: pixelSizes(screens),
                            hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
}

/// Full size: the zoom path before zoom decoded per step, and still the one for 100 % and above.
func fullDecode(_ url: URL) throws -> CGImage {
    try ImageDecoder.decode(url, maxPixelSize: nil, halvingSteps: true, hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
}

/// The viewer's zoom decode at `factor`, as `ViewerModel` asks `ImageCache` for it (`.step`), header read included.
func zoomDecode(_ url: URL, factor: Double) throws -> CGImage {
    let size = ImageDecoder.displaySize(of: url) ?? .zero
    let step = ImageDecoder.zoomStep(full: Int(max(size.width, size.height)), factor: factor)
    return try ImageDecoder.decode(url, halvingSteps: true, step: step, hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
}
let zoomFactors = [0.25, 0.5, 1.0]

// MARK: - Arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("Missing mode or folder.") }
let mode = arguments.removeFirst()
let folder = URL(fileURLWithPath: arguments.removeFirst())
guard knownOptions[mode] != nil else { fail("Unknown mode \(mode).") }
let options: [String: [String]]
do { options = try parseOptions(arguments, mode: mode) } catch { fail(error.message) }
@MainActor func option(_ name: String) -> String? { options[name]?.last }
@MainActor func screens(default defaults: [String]) -> [Screen] {
    (options["--screen"] ?? defaults).map { text in
        guard let screen = Screen(text) else { fail("Bad screen size \(text), expected WxH.") }
        return screen
    }
}

@MainActor func decimal(_ name: String, default value: Double) -> Double {
    guard let text = option(name) else { return value }
    guard let number = Double(text), number > 0 else { fail("Bad \(name) \(text), expected a number above 0.") }
    return number
}

@MainActor func number(_ name: String, default value: Int) -> Int {
    guard let text = option(name) else { return value }
    guard let number = Int(text), number > 0 else { fail("Bad \(name) \(text), expected a whole number above 0.") }
    return number
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
}

func f(_ value: Double) -> String { String(format: "%.1f", value) }

func imageFiles(in dir: URL) -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: .skipsHiddenFiles)) ?? []
    return urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        && ImageDecoder.displaySize(of: $0) != nil }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

// MARK: - decode

@MainActor func runDecode() {
    let screens = screens(default: ["3024x1964", "3456x2234", "5120x2880"])
    let runs = number("--runs", default: 10)
    var files = imageFiles(in: folder)
    if let raw = option("--raw") { files += imageFiles(in: URL(fileURLWithPath: raw)) }
    guard !files.isEmpty else { fail("No images in \(folder.path). Run `corpus` first.") }

    func measure(_ file: URL, screen: String, _ decode: () throws -> CGImage) -> Row? {
        var times: [Double] = []
        var last: CGImage?
        for _ in 0...runs {
            let start = ContinuousClock.now
            guard let image = try? decode() else {
                print("Can't decode \(file.lastPathComponent)")
                return nil
            }
            times.append(start.duration(to: .now).milliseconds)
            last = image
        }
        let first = times.removeFirst()
        let sorted = times.sorted()
        return Row(file: file.lastPathComponent, screen: screen, width: last?.width ?? 0, height: last?.height ?? 0,
                   megabytes: Double((last?.bytesPerRow ?? 0) * (last?.height ?? 0)) / 1_000_000,
                   firstMs: first, medianMs: percentile(sorted, 0.5), p95Ms: percentile(sorted, 0.95), minMs: sorted[0])
    }

    print("file\tscreen\tdecoded\tMB\tfirst ms\tmedian\tp95\tmin")
    var rows: [Row] = []
    for file in files {
        var fileRows = screens.compactMap { screen in measure(file, screen: "\(screen)") { try fitDecode(file, screens: [screen]) } }
        if let full = measure(file, screen: "full", { try fullDecode(file) }) { fileRows.append(full) }
        if file.lastPathComponent.hasPrefix("50mp") {
            fileRows += zoomFactors.compactMap { factor in measure(file, screen: "zoom \(factor)") { try zoomDecode(file, factor: factor) } }
        }
        for row in fileRows {
            print([row.file, row.screen, "\(row.width)×\(row.height)", f(row.megabytes), f(row.firstMs),
                   f(row.medianMs), f(row.p95Ms), f(row.minMs)].joined(separator: "\t"))
        }
        rows += fileRows
    }

    report(rows)
}

/// `--json` writes the rows, `--baseline` compares them (exits 1 if a median is > 10 % slower or a row is gone).
@MainActor func report(_ rows: [Row]) {
    if let path = option("--json") {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: path))
        } catch {
            fail("Can't write \(path).")
        }
    }
    if let path = option("--baseline") {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let baseline = try? JSONDecoder().decode([Row].self, from: data) else { fail("Can't read \(path).") }
        let failures = baselineFailures(rows, baseline: baseline)
        failures.forEach { print($0) }
        if !failures.isEmpty { exit(1) }
        print("No median is more than 10 % slower than \(path).")
    }
}

// MARK: - browse

struct Step: Sendable {
    let index: Int
    let file: String
    let cached: Bool
    let ms: Double?  // nil: superseded before its image arrived
}

@MainActor func runBrowse() async {
    let screen = screens(default: ["3024x1964"])
    let interval = number("--interval-ms", default: 300)
    let urls = imageFiles(in: folder)
    guard !urls.isEmpty else { fail("No images in \(folder.path). Run `corpus` first.") }
    let target = DecodeTarget.fit(pixelSizes(screen))
    // As ViewerModel sets up its fit cache.
    let decodes = DecodeQueue()
    let cache = ImageCache(capacity: 8, hdr: ImageDecoder.supportsHDR, colorSpace: displayP3, queue: decodes)
    var list = ImageList(urls: urls)
    var steps: [Task<Step, Never>] = []
    var peak: UInt64 = 0, peakCache = 0
    func sample() async {
        peak = max(peak, memoryFootprint())
        peakCache = max(peakCache, await cache.decodedBytes)
    }

    // As ViewerModel.show(): cancel the last step, focus the queue, await the image, then prefetch the neighbours.
    for index in urls.indices {
        let start = ContinuousClock.now
        steps.last?.cancel()
        guard let url = list.current else { break }
        let neighbors = list.neighbors(radius: 2, forward: true)
        decodes.focus([url] + neighbors)
        let cached = await cache.contains(url)
        steps.append(Task {
            let image = try? await cache.image(for: url, target: target)
            let elapsed = start.duration(to: .now).milliseconds
            guard image != nil, !Task.isCancelled else {
                return Step(index: index, file: url.lastPathComponent, cached: cached, ms: nil)
            }
            await cache.prefetch(neighbors, target: target)
            return Step(index: index, file: url.lastPathComponent, cached: cached, ms: elapsed)
        })
        await sample()
        try? await Task.sleep(until: start + .milliseconds(interval), clock: .continuous)
        list.next()
    }
    var results: [Step] = []
    for step in steps { results.append(await step.value) }
    await sample()

    print("step\tfile\tcached\tms")
    for step in results {
        print("\(step.index + 1)\t\(step.file)\t\(step.cached ? "yes" : "no")\t\(step.ms.map(f) ?? "superseded")")
    }
    func summary(_ label: String, _ steps: [Step]) {
        let times = steps.compactMap(\.ms).sorted()
        guard !times.isEmpty else { return print("\(label): none returned") }
        print("\(label): \(times.count) returned, median \(f(percentile(times, 0.5))) ms, "
              + "p95 \(f(percentile(times, 0.95))) ms, max \(f(times.last!)) ms")
    }
    print("")
    summary("all", results)
    summary("cached", results.filter(\.cached))
    summary("not cached", results.filter { !$0.cached })
    print("superseded: \(results.filter { $0.ms == nil }.count) of \(results.count)")
    // The footprint leaves out the cache's decoded images (purgeable volatile), so both are reported.
    print("peak cache: \(peakCache / 1_000_000) MB decoded, peak footprint: \(peak / 1_000_000) MB (screen \(screen[0]), every \(interval) ms)")
}

// MARK: - grid

@MainActor func runGrid() async {
    let points = decimal("--points", default: ThumbnailSize.standard)
    let scale = decimal("--scale", default: 2)
    let cells = number("--cells", default: 40)
    // Decision 8's grid queue, as the app sets it up.
    let width = number("--width", default: max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
    let urls = Array(((try? FolderScanner.images(around: folder)) ?? []).prefix(cells))
    guard !urls.isEmpty else { fail("No images in \(folder.path). Run `corpus` first.") }
    let side = ThumbnailSize.decodeSide(points: points, scale: scale)
    let target = DecodeTarget.thumbnail(side)
    let decodes = DecodeQueue(width: width)
    let cache = ImageCache(capacity: urls.count, colorSpace: displayP3, queue: decodes,
                           byteBudget: ThumbnailSize.cacheBudget(screens: [PixelSize(width: 3024, height: 1964)]))

    // All cells at once, as a first screen asks; each file's time runs from that moment, as its cell sees it.
    let start = ContinuousClock.now
    decodes.focus(urls)
    let times = await withTaskGroup(of: (String, Double?).self) { group in
        for url in urls {
            group.addTask {
                let image = try? await cache.image(for: url, target: target)
                return (url.lastPathComponent, image.map { _ in start.duration(to: .now).milliseconds })
            }
        }
        var times: [(String, Double?)] = []
        for await time in group { times.append(time) }
        return times
    }
    let total = start.duration(to: .now).milliseconds
    let failed = times.filter { $0.1 == nil }.map(\.0)
    failed.forEach { print("Can't decode \($0)") }
    let sorted = times.compactMap(\.1).sorted()
    let megabytes = Double(await cache.decodedBytes) / 1_000_000
    print("\(urls.count) files, \(f(points)) pt at \(f(scale))×, side \(side) px, width \(width)")
    print("total \(f(total)) ms, per file p50 \(f(percentile(sorted, 0.5))) ms, p95 \(f(percentile(sorted, 0.95))) ms")
    print("cache: \(f(megabytes)) MB decoded")

    let file = "\(urls.count) files", screen = "grid \(side)"
    report([
        Row(file: file, screen: screen + " total", width: side, height: side, megabytes: megabytes,
            firstMs: total, medianMs: total, p95Ms: total, minMs: total),
        Row(file: file, screen: screen + " per file", width: side, height: side, megabytes: megabytes,
            firstMs: sorted.first ?? 0, medianMs: percentile(sorted, 0.5), p95Ms: percentile(sorted, 0.95),
            minMs: sorted.first ?? 0),
    ])
    if !failed.isEmpty { exit(1) }
}

switch mode {
case "corpus":
    do {
        try Corpus.write(to: folder)
    } catch {
        fail("Can't write the corpus to \(folder.path).")
    }
case "decode": runDecode()
case "browse": await runBrowse()
case "grid": await runGrid()
case "fuzz": runFuzz()
case "thumbnail": await runThumbnail(folder, out: option("--out").map { URL(fileURLWithPath: $0) })
default: fail("Unknown mode \(mode).")
}
