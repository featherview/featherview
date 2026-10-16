import Foundation

public struct BatchJob: Sendable {
    public var inputs: [URL]
    public var outputFolder: URL
    public var format: OutputFormat
    /// The format's options (spec "Format options"); its defaults unless given.
    public var options: FormatOptions
    /// Longest side in pixels; nil keeps the size. Never upscales.
    public var maxDimension: Int?
    /// nil keeps the original base name.
    public var rename: RenamePattern?

    public init(inputs: [URL], outputFolder: URL, format: OutputFormat, options: FormatOptions? = nil,
                maxDimension: Int? = nil, rename: RenamePattern? = nil) {
        self.inputs = inputs
        self.outputFolder = outputFolder
        self.format = format
        self.options = options ?? format.defaultOptions
        self.maxDimension = maxDimension
        self.rename = rename
    }
}

public enum BatchPlanner {
    /// One output URL per input, in input order. Never an existing file, never an input,
    /// never the same name twice: clashes get " 2", " 3", ... appended.
    public static func outputURLs(
        for job: BatchJob,
        // attributesOfItem doesn't follow symlinks, so a dangling link still counts as taken.
        fileExists: (URL) -> Bool = { (try? FileManager.default.attributesOfItem(atPath: $0.path)) != nil }
    ) -> [URL] {
        var taken = Set(job.inputs.map(pathKey))
        // Resolve the folder once: pathKey per probe hits the filesystem and made clashes quadratic.
        let folderKey = pathKey(job.outputFolder)
        func key(_ url: URL) -> String { folderKey + "/" + url.lastPathComponent.lowercased() }
        var nextSuffix: [String: Int] = [:]
        return job.inputs.enumerated().map { offset, input in
            let original = input.deletingPathExtension().lastPathComponent
            let base = job.rename?.baseName(original: original, index: offset + 1) ?? original
            func candidate(_ suffix: String) -> URL {
                // APFS names are at most 255 bytes: shorten the base, whole characters only.
                // Measured decomposed, because file URLs store names that way (é is 3 bytes).
                func bytes(_ s: some StringProtocol) -> Int { s.decomposedStringWithCanonicalMapping.utf8.count }
                let room = 255 - bytes(suffix + "." + job.format.fileExtension)
                var trimmed = Substring(base)
                while bytes(trimmed) > room { trimmed = trimmed.dropLast() }
                return job.outputFolder.appendingPathComponent(trimmed + suffix)
                    .appendingPathExtension(job.format.fileExtension)
            }
            var url = candidate("")
            var counter = nextSuffix[base.lowercased()] ?? 2
            while taken.contains(key(url)) || fileExists(url) {
                url = candidate(" \(counter)")
                counter += 1
            }
            nextSuffix[base.lowercased()] = counter
            taken.insert(key(url))
            return url
        }
    }
}
