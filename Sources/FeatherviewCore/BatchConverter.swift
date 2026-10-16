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
        let outputs = BatchPlanner.outputURLs(for: job)
        let total = job.inputs.count
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        var results = [BatchResult?](repeating: nil, count: total)
        await withTaskGroup(of: (Int, BatchResult).self) { group in
            var started = 0
            var done = 0
            while started < min(width, total) {
                let i = started
                group.addTask { (i, convert(job.inputs[i], to: outputs[i], job: job)) }
                started += 1
            }
            for await (i, result) in group {
                results[i] = result
                done += 1
                progress(done, total)
                if started < total {
                    let next = started
                    group.addTask { (next, convert(job.inputs[next], to: outputs[next], job: job)) }
                    started += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    static func convert(_ input: URL, to output: URL, job: BatchJob) -> BatchResult {
        do {
            let image = try ImageDecoder.decode(input, maxPixelSize: job.maxDimension)
            guard let dest = CGImageDestinationCreateWithURL(
                output as CFURL, job.format.type.identifier as CFString, 1, nil)
            else { return BatchResult(input: input, output: output, error: "Can't write \(job.format.rawValue.uppercased())") }
            CGImageDestinationAddImage(dest, image, properties(of: input, job: job) as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                try? FileManager.default.removeItem(at: output)  // never leave a half-written file
                return BatchResult(input: input, output: output, error: "Writing failed")
            }
            return BatchResult(input: input, output: output, error: nil)
        } catch {
            return BatchResult(input: input, output: output, error: "Can't read this image")
        }
    }

    /// Keeps EXIF, GPS and IPTC; drops what no longer matches the new pixels.
    static func properties(of input: URL, job: BatchJob) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(input as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
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
