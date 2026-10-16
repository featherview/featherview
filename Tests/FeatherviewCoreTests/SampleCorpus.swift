import Foundation
@testable import FeatherviewCore

/// The real sample files (not committed), for opt-in suites that are skipped when they aren't on disk.
/// Point `FEATHERVIEW_SAMPLES` at the folder that holds `xcf/`, `psb/`, `psp/` and `pdn/`.
enum SampleCorpus {
    static let root: URL? = {
        guard let path = ProcessInfo.processInfo.environment["FEATHERVIEW_SAMPLES"], !path.isEmpty else { return nil }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var isAvailable: Bool { root != nil }

    /// `<folder>/ref/<file name>.png`
    static func reference(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("ref").appendingPathComponent(file.lastPathComponent + ".png")
    }

    /// Both images composited over white, mean absolute difference per colour channel (0…255);
    /// `.infinity` when the sizes differ.
    static func difference(_ a: RGBAImage, _ b: RGBAImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        guard !a.pixels.isEmpty else { return 0 }
        func overWhite(_ p: [UInt8], _ i: Int) -> Double {
            let alpha = Double(p[i - i % 4 + 3]) / 255
            return Double(p[i]) * alpha + 255 * (1 - alpha)
        }
        var total = 0.0
        for i in 0..<a.pixels.count where i % 4 != 3 { total += abs(overWhite(a.pixels, i) - overWhite(b.pixels, i)) }
        return total / Double(a.width * a.height * 3)
    }
}
