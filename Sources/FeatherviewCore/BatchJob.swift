import Foundation
import UniformTypeIdentifiers

public enum OutputFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic, tiff

    public var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    public var isLossy: Bool { self == .jpeg || self == .heic }
}

public struct BatchJob: Sendable {
    public var inputs: [URL]
    public var outputFolder: URL
    public var format: OutputFormat
    /// 0...1, lossy formats only.
    public var quality: Double
    /// Longest side in pixels; nil keeps the size. Never upscales.
    public var maxDimension: Int?
    /// nil keeps the original base name.
    public var rename: RenamePattern?

    public init(inputs: [URL], outputFolder: URL, format: OutputFormat, quality: Double = 0.85,
                maxDimension: Int? = nil, rename: RenamePattern? = nil) {
        self.inputs = inputs
        self.outputFolder = outputFolder
        self.format = format
        self.quality = quality
        self.maxDimension = maxDimension
        self.rename = rename
    }
}

public enum BatchPlanner {
    /// One output URL per input, in input order. Never an existing file, never an input,
    /// never the same name twice: clashes get " 2", " 3", ... appended.
    public static func outputURLs(
        for job: BatchJob,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [URL] {
        var taken = Set(job.inputs.map(pathKey))
        return job.inputs.enumerated().map { offset, input in
            let original = input.deletingPathExtension().lastPathComponent
            let base = job.rename?.baseName(original: original, index: offset + 1) ?? original
            func candidate(_ suffix: String) -> URL {
                job.outputFolder.appendingPathComponent(base + suffix)
                    .appendingPathExtension(job.format.fileExtension)
            }
            var url = candidate("")
            var counter = 2
            while taken.contains(pathKey(url)) || fileExists(url) {
                url = candidate(" \(counter)")
                counter += 1
            }
            taken.insert(pathKey(url))
            return url
        }
    }
}
