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

    corpus  writes generated test images into <dir> (never commit them).
    decode  times the viewer's fit decode per file and screen, plus one full-size decode per file.
            The first run reads the file from disk; for a truly cold first run, run `sudo purge`
            before (the bench never does). --baseline exits 1 if a median is > 10 % slower or a row is gone.
    browse  steps through the folder like a held arrow key: one step every --interval-ms, whether
            or not the last one finished, through an 8-image cache with 2 neighbours prefetched each way.
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

/// The longest side the viewer decodes at in fit mode, for these screens (today: the longest side of any).
func fitPixels(_ screens: [Screen]) -> Int {
    screens.map { max($0.width, $0.height) }.max() ?? 2560
}

/// The viewer's fit decode, exactly as `ViewerModel` and `ImageCache` call it. Keep it the one place this call
/// lives: a change to the fit rule changes only this function, so before and after stay comparable.
func fitDecode(_ url: URL, screens: [Screen]) throws -> CGImage {
    try ImageDecoder.decode(url, maxPixelSize: fitPixels(screens), halvingSteps: true,
                            hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
}

/// Today's zoom path: full size.
func fullDecode(_ url: URL) throws -> CGImage {
    try ImageDecoder.decode(url, maxPixelSize: nil, halvingSteps: true, hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
}

// MARK: - Arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("Missing mode or folder.") }
let mode = arguments.removeFirst()
let folder = URL(fileURLWithPath: arguments.removeFirst())
var options: [String: [String]] = [:]
while !arguments.isEmpty {
    let name = arguments.removeFirst()
    guard name.hasPrefix("--"), !arguments.isEmpty else { fail("Unexpected argument \(name).") }
    options[name, default: []].append(arguments.removeFirst())
}
@MainActor func option(_ name: String) -> String? { options[name]?.last }
@MainActor func screens(default defaults: [String]) -> [Screen] {
    (options["--screen"] ?? defaults).map { text in
        guard let screen = Screen(text) else { fail("Bad screen size \(text), expected WxH.") }
        return screen
    }
}

@MainActor func number(_ name: String, default value: Int) -> Int {
    guard let text = option(name) else { return value }
    guard let number = Int(text), number > 0 else { fail("Bad \(name) \(text), expected a whole number above 0.") }
    return number
}

func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
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
            times.append(ms(start.duration(to: .now)))
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
        for row in fileRows {
            print([row.file, row.screen, "\(row.width)×\(row.height)", f(row.megabytes), f(row.firstMs),
                   f(row.medianMs), f(row.p95Ms), f(row.minMs)].joined(separator: "\t"))
        }
        rows += fileRows
    }

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
    let size = fitPixels(screen)
    // As ViewerModel sets up its fit cache.
    let cache = ImageCache(capacity: 8, hdr: ImageDecoder.supportsHDR, colorSpace: displayP3)
    var list = ImageList(urls: urls)
    var steps: [Task<Step, Never>] = []
    var peak: (footprint: UInt64, volatile: UInt64) = (0, 0)
    func sample() {
        let now = memoryUse()
        peak = (max(peak.footprint, now.footprint), max(peak.volatile, now.volatile))
    }

    // As ViewerModel.show(): cancel the last step, await the image, then prefetch the neighbours.
    for index in urls.indices {
        let start = ContinuousClock.now
        steps.last?.cancel()
        guard let url = list.current else { break }
        let neighbors = list.neighbors(radius: 2)
        let cached = await cache.contains(url)
        steps.append(Task {
            let image = try? await cache.image(for: url, maxPixelSize: size)
            let elapsed = ms(start.duration(to: .now))
            guard image != nil, !Task.isCancelled else {
                return Step(index: index, file: url.lastPathComponent, cached: cached, ms: nil)
            }
            await cache.prefetch(neighbors, maxPixelSize: size)
            return Step(index: index, file: url.lastPathComponent, cached: cached, ms: elapsed)
        })
        sample()
        try? await Task.sleep(until: start + .milliseconds(interval), clock: .continuous)
        list.next()
    }
    var results: [Step] = []
    for step in steps { results.append(await step.value) }
    sample()

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
    print("peak footprint: \(peak.footprint / 1_000_000) MB, peak purgeable volatile: \(peak.volatile / 1_000_000) MB "
          + "(screen \(screen[0]), every \(interval) ms)")
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
default: fail("Unknown mode \(mode).")
}
