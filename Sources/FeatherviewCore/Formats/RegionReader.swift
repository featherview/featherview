import CoreGraphics
import Foundation

/// An own reader for huge pictures that decodes any part of the picture straight from the file, area-averaged
/// to the size asked for (`PSDComposite`, `TIFFRaster`).
public protocol RegionReader: Sendable {
    var width: Int { get }
    var height: Int { get }
    /// The file's ICC profile, nil without one.
    var icc: Data? { get }
    /// `region` in full-size pixels (integral, inside the picture; nil = the whole picture), area-averaged to
    /// `size`, which is clamped to at most the region and at least 1 × 1 per side. 8-bit RGB in the file's
    /// ICC profile (sRGB without a usable one). Throws `OwnDecodeError.corrupt` on any short read or bad data.
    func decode(region: CGRect?, size: PixelSize) throws -> CGImage
}

extension RegionReader {
    public func decode(size: PixelSize) throws -> CGImage { try decode(region: nil, size: size) }

    /// `region` clamped to the picture (`x0`, `y0`, `rw`, `rh`) and `size` clamped to it (`ow`, `oh`).
    func bounds(_ region: CGRect?, size: PixelSize) throws -> (x0: Int, y0: Int, rw: Int, rh: Int, ow: Int, oh: Int) {
        let rect = (region ?? CGRect(x: 0, y: 0, width: width, height: height)).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { throw OwnDecodeError.corrupt }
        let rw = Int(rect.width), rh = Int(rect.height)
        return (Int(rect.minX), Int(rect.minY), rw, rh, min(max(size.width, 1), rw), min(max(size.height, 1), rh))
    }

    /// `output` (`ow × oh` RGBX pixels, which the image takes over) as an image in the ICC profile or sRGB.
    func image(_ output: UnsafeMutableBufferPointer<UInt8>, ow: Int, oh: Int) throws -> CGImage {
        let data = Data(bytesNoCopy: output.baseAddress!, count: output.count, deallocator: .custom { pointer, _ in pointer.deallocate() })
        let space = icc.flatMap { CGColorSpace(iccData: $0 as CFData) }.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow * 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw OwnDecodeError.corrupt }
        return image
    }
}

/// Positional file reads for the region readers.
enum FileRead {
    /// `count` bytes at `offset`; throws on an error or the end of the file before them.
    static func bytes(_ fd: Int32, _ offset: Int, _ count: Int) throws -> [UInt8] {
        try [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            try read(fd, offset, count, into: buffer.baseAddress!)
            initialized = count
        }
    }

    /// `count` bytes at `offset` into `buffer`; throws on an error or the end of the file before them.
    static func read(_ fd: Int32, _ offset: Int, _ count: Int, into buffer: UnsafeMutablePointer<UInt8>) throws {
        guard offset >= 0, count >= 0 else { throw OwnDecodeError.corrupt }
        var done = 0
        while done < count {
            let n = pread(fd, buffer + done, count - done, off_t(offset + done))
            guard n > 0 else { throw OwnDecodeError.corrupt }
            done += n
        }
    }
}
