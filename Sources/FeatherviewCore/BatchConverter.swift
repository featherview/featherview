import Foundation
import ImageIO

public struct BatchResult: Sendable {
    public let input: URL
    public let output: URL
    /// nil = converted.
    public let error: String?
}

public enum BatchConverter {
    /// Converts every input, several at a time. One failure never stops the batch.
    /// `progress(done, total)` is called off the main thread.
    public static func run(
        _ job: BatchJob,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [BatchResult] {
        await run(job, progress: progress) { convert($0, to: $1, job: $2) }
    }

    /// `convert` is a seam for tests.
    static func run(
        _ job: BatchJob,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        convert: @escaping @Sendable (URL, URL, BatchJob) -> BatchResult
    ) async -> [BatchResult] {
        let outputs = BatchPlanner.outputURLs(for: job)
        let total = job.inputs.count
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        var results = [BatchResult?](repeating: nil, count: total)
        await withTaskGroup(of: (Int, BatchResult).self) { group in
            var started = 0
            var done = 0
            while started < min(width, total) {
                let i = started
                group.addTask { (i, await offPool { convert(job.inputs[i], outputs[i], job) }) }
                started += 1
            }
            for await (i, result) in group {
                results[i] = result
                done += 1
                progress(done, total)
                if started < total {
                    let next = started
                    group.addTask { (next, await offPool { convert(job.inputs[next], outputs[next], job) }) }
                    started += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    /// Blocking ImageIO work runs on GCD, so it never ties up the cooperative pool the viewer's
    /// decode tasks need. The task group still caps how many run at once.
    private static func offPool(_ work: @escaping @Sendable () -> BatchResult) async -> BatchResult {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: work()) }
        }
    }

    static func convert(_ input: URL, to output: URL, job: BatchJob) -> BatchResult {
        let image: CGImage
        do { image = try ImageDecoder.decode(input, maxPixelSize: job.maxDimension) }
        catch { return BatchResult(input: input, output: output, error: "Can't read this image") }
        // Encode to a hidden temp file, then move it in without replacing: a kill mid-write never
        // leaves a partial file under the real name, and a file that appeared there is never touched.
        let temp = output.deletingLastPathComponent().appendingPathComponent(".featherview-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let dest = CGImageDestinationCreateWithURL(
            temp as CFURL, job.format.type.identifier as CFString, 1, nil)
        else { return BatchResult(input: input, output: output, error: "Can't write \(job.format.rawValue.uppercased())") }
        CGImageDestinationAddImage(dest, image, properties(of: input, job: job) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return BatchResult(input: input, output: output, error: "Writing failed")
        }
        let base = output.deletingPathExtension().lastPathComponent
        var target = output
        // shortcut: no 255-byte trim on the retry names, so a near-limit name fails instead; trim if anyone hits it.
        for counter in 2...10_000 {
            if renamex_np(temp.path, target.path, UInt32(RENAME_EXCL)) == 0 {
                return BatchResult(input: input, output: target, error: nil)
            }
            guard errno == EEXIST else { break }
            target = output.deletingLastPathComponent().appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(output.pathExtension)
        }
        return BatchResult(input: input, output: output, error: "Writing failed")
    }

    /// Keeps TIFF (camera make/model), EXIF, GPS and IPTC; drops what no longer matches the new pixels.
    static func properties(of input: URL, job: BatchJob) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(input as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if var tiff = original[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = nil  // camera make/model, copyright, ...
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = original[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = nil
                exif[kCGImagePropertyExifPixelYDimension] = nil
                props[kCGImagePropertyExifDictionary] = exif
            }
            props[kCGImagePropertyGPSDictionary] = original[kCGImagePropertyGPSDictionary]
            props[kCGImagePropertyIPTCDictionary] = original[kCGImagePropertyIPTCDictionary]
        }
        props[kCGImagePropertyOrientation] = 1  // decode already rotated the pixels upright
        if job.format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = job.quality }
        return props
    }
}
