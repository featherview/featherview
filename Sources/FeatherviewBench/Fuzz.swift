import FeatherviewCore
import Foundation
import os

// featherview-bench fuzz: mutated seeds through the own decoders, as the viewer calls them. A crash kills the
// process with `current.<ext>` still on disk (scripts/fuzz.sh keeps it); a hang is copied and exits 3.

/// The input being decoded and when it started, for the watchdog.
private let decoding = OSAllocatedUnfairLock<(start: ContinuousClock.Instant, file: URL)?>(initialState: nil)

@MainActor func runFuzz() {
    guard let outPath = option("--out") else { fail("Missing --out <dir>.") }
    let out = URL(fileURLWithPath: outPath, isDirectory: true)
    let seconds = decimal("--seconds", default: 60)
    let seed: UInt64
    if let text = option("--seed") {
        guard let value = UInt64(text) else { fail("Bad --seed \(text), expected a whole number.") }
        seed = value
    } else {
        seed = UInt64.random(in: 0...UInt64.max)
    }
    var isFolder: ObjCBool = false
    FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder)
    let files = isFolder.boolValue
        ? ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        : [folder]
    let seeds = files.compactMap { url -> (url: URL, format: OwnFormat, data: Data)? in
        guard let format = OwnDecoders.format(for: url), let data = try? Data(contentsOf: url) else { return nil }
        return (url, format, data)
    }
    guard !seeds.isEmpty else { fail("No seeds for an own format in \(folder.path).") }
    do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) } catch { fail("Can't create \(out.path).") }

    let watchdog = Thread {
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            guard let current = decoding.withLock({ $0 }), current.start.duration(to: .now) > .seconds(5) else { continue }
            let hang = numbered("hang", ext: current.file.pathExtension, in: out)
            try? FileManager.default.copyItem(at: current.file, to: hang)
            print("hang: \(hang.lastPathComponent) took over 5 s")
            exit(3)
        }
    }
    watchdog.start()

    print("fuzz \(seeds.map(\.url.lastPathComponent).joined(separator: ", ")) for \(f(seconds)) s, seed \(seed)")
    var mutator = FuzzMutator(seed: seed)
    let end = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    var inputs = 0
    while ContinuousClock.now < end {
        for entry in seeds {
            let data = mutator.mutate(entry.data)
            let current = out.appendingPathComponent("current.\(entry.url.pathExtension)")
            do { try data.write(to: current) } catch { fail("Can't write \(current.path).") }
            decoding.withLock { $0 = (.now, current) }
            _ = entry.format.size(data, 0)
            for page in 0..<min(entry.format.pageCount(data), 3) {
                _ = try? entry.format.decode(data, page, nil)
                _ = try? entry.format.decode(data, page, 512)
            }
            decoding.withLock { $0 = nil }
            inputs += 1
        }
    }
    for entry in seeds { try? FileManager.default.removeItem(at: out.appendingPathComponent("current.\(entry.url.pathExtension)")) }
    print("inputs \(inputs)")
}

/// `<out>/<prefix>-<n>.<ext>` with the first n not taken, so a restarted run never overwrites a finding.
func numbered(_ prefix: String, ext: String, in out: URL) -> URL {
    var n = 1
    while FileManager.default.fileExists(atPath: out.appendingPathComponent("\(prefix)-\(n).\(ext)").path) { n += 1 }
    return out.appendingPathComponent("\(prefix)-\(n).\(ext)")
}
