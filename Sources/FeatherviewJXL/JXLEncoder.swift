import CJPEGXL
import CoreGraphics
import FeatherviewCore
import Foundation
import os

/// JPEG XL through libjxl (ImageIO reads it but can't write it).
public enum JXLEncoder {
    /// One 12 MP encode peaks at about 550 MB in libjxl; more at once buys little speed.
    static let maxConcurrentEncodes = 2
    private static let slots = DispatchSemaphore(value: maxConcurrentEncodes)
    private static let inFlight = OSAllocatedUnfairLock(initialState: (now: 0, peak: 0))

    /// Highest number of encodes inside libjxl at once since `resetPeakInFlight()`.
    static var peakInFlight: Int { inFlight.withLock { $0.peak } }
    static func resetPeakInFlight() { inFlight.withLock { $0.peak = $0.now } }

    /// `quality` 1...100 (ignored when lossless), `effort` 1...9; out-of-range values are clamped.
    /// `xmp` goes into an `xml ` box. Writes in the image's own RGB colour space, else sRGB; 16 bits
    /// when the image has more than 8, alpha (premultiplied) only when the image has it.
    /// Blocks while `maxConcurrentEncodes` others run: call it off the cooperative pool.
    public static func encode(_ image: CGImage, quality: Int, lossless: Bool, effort: Int, xmp: Data?) throws -> Data {
        let deep = image.bitsPerComponent > 8
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var space = srgb
        if let own = image.colorSpace, own.model == .rgb, !CGColorSpaceUsesExtendedRange(own),
           !CGColorSpaceUsesITUR_2100TF(own), own.copyICCData() != nil {
            space = own
        }
        let isSRGB = space.name == CGColorSpace.sRGB
        let icc = isSRGB ? nil : space.copyICCData() as Data?
        let pixels = try draw(image, in: space, deep: deep, keepAlpha: hasAlpha)

        slots.wait()
        inFlight.withLock { $0.now += 1; $0.peak = max($0.peak, $0.now) }
        defer {
            inFlight.withLock { $0.now -= 1 }
            slots.signal()
        }

        guard let encoder = JxlEncoderCreate(nil) else { throw EncodeError.failed }
        defer { JxlEncoderDestroy(encoder) }
        let runner = JxlThreadParallelRunnerCreate(nil, JxlThreadParallelRunnerDefaultNumWorkerThreads())
        defer { JxlThreadParallelRunnerDestroy(runner) }
        try check(JxlEncoderSetParallelRunner(encoder, JxlThreadParallelRunner, runner))

        let bits = UInt32(deep ? 16 : 8)
        var info = JxlBasicInfo()
        JxlEncoderInitBasicInfo(&info)
        info.xsize = UInt32(image.width)
        info.ysize = UInt32(image.height)
        info.bits_per_sample = bits
        info.num_color_channels = 3
        info.uses_original_profile = lossless ? 1 : 0
        info.orientation = JXL_ORIENT_IDENTITY
        if hasAlpha {
            info.num_extra_channels = 1
            info.alpha_bits = bits
            info.alpha_premultiplied = 1
        }
        try check(JxlEncoderSetBasicInfo(encoder, &info))
        if let icc {
            try icc.withUnsafeBytes {
                try check(JxlEncoderSetICCProfile(encoder, $0.bindMemory(to: UInt8.self).baseAddress, $0.count))
            }
        } else {
            var color = JxlColorEncoding()
            JxlColorEncodingSetToSRGB(&color, 0)
            try check(JxlEncoderSetColorEncoding(encoder, &color))
        }

        guard let settings = JxlEncoderFrameSettingsCreate(encoder, nil) else { throw EncodeError.failed }
        try check(JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, Int64(min(max(effort, 1), 9))))
        if lossless {
            try check(JxlEncoderSetFrameLossless(settings, 1))
        } else {
            // libjxl gives distance 0 at quality 100: not lossless, and bigger than 99's 0.19.
            let distance = max(JxlEncoderDistanceFromQuality(Float(min(max(quality, 1), 100))), 0.1)
            try check(JxlEncoderSetFrameDistance(settings, distance))
        }

        // Ahead of the frame: added after it, ImageIO doesn't see the box.
        if let xmp {
            try check(JxlEncoderUseBoxes(encoder))
            try xmp.withUnsafeBytes {
                try check(JxlEncoderAddBox(encoder, "xml ", $0.bindMemory(to: UInt8.self).baseAddress, $0.count, 0))
            }
        }

        var format = JxlPixelFormat(num_channels: hasAlpha ? 4 : 3, data_type: deep ? JXL_TYPE_UINT16 : JXL_TYPE_UINT8,
                                    endianness: JXL_NATIVE_ENDIAN, align: 0)
        try pixels.withUnsafeBytes {
            try check(JxlEncoderAddImageFrame(settings, &format, $0.baseAddress, $0.count))
        }
        JxlEncoderCloseInput(encoder)

        var output = [UInt8](repeating: 0, count: 64 * 1024)
        var used = 0
        while true {
            let status = output.withUnsafeMutableBufferPointer { buffer -> JxlEncoderStatus in
                var next: UnsafeMutablePointer<UInt8>? = buffer.baseAddress! + used
                var available = buffer.count - used
                let status = JxlEncoderProcessOutput(encoder, &next, &available)
                used = buffer.count - available
                return status
            }
            if status == JXL_ENC_SUCCESS { break }
            guard status == JXL_ENC_NEED_MORE_OUTPUT else { throw EncodeError.failed }
            output.append(contentsOf: repeatElement(0, count: output.count))
        }
        return Data(output[..<used])
    }

    private static func check(_ status: JxlEncoderStatus) throws {
        guard status == JXL_ENC_SUCCESS else { throw EncodeError.failed }
    }

    /// Upright pixels as RGBA (premultiplied) or RGB, 8 or 16 bits per sample in native byte order.
    private static func draw(_ image: CGImage, in space: CGColorSpace, deep: Bool, keepAlpha: Bool) throws -> Data {
        let (width, height) = (image.width, image.height)
        let sampleBytes = deep ? 2 : 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | (deep ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: deep ? 16 : 8,
                                      bytesPerRow: width * 4 * sampleBytes, space: space, bitmapInfo: bitmapInfo),
              let base = context.data
        else { throw EncodeError.failed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rgba = UnsafeRawBufferPointer(start: base, count: width * height * 4 * sampleBytes)
        if keepAlpha { return Data(rgba) }
        let pixelBytes = 4 * sampleBytes, keep = 3 * sampleBytes
        var rgb = Data(count: width * height * keep)
        rgb.withUnsafeMutableBytes { out in
            for i in 0..<(width * height) {
                out.baseAddress!.advanced(by: i * keep)
                    .copyMemory(from: rgba.baseAddress!.advanced(by: i * pixelBytes), byteCount: keep)
            }
        }
        return rgb
    }
}
