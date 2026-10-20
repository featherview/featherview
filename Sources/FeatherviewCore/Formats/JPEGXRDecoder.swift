import CJPEGXR
import Foundation

/// JPEG XR (also HD Photo / Windows Media Photo: .jxr, .wdp, .hdp) through jxrlib. Every pixel format
/// is brought to 8 bits per channel; HDR and wide-gamut files are clipped to sRGB, an embedded colour
/// profile is ignored.
// shortcut: sRGB 8-bit output, add a float path with the file's profile if people open HDR JPEG XR files.
enum JPEGXRDecoder {
    static let format = OwnFormat.raster(name: "JPEG XR", extensions: ["jxr", "wdp", "hdp"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var width: Int32 = 0, height: Int32 = 0
        try check(data.withUnsafeBytes { fv_jxr_size($0.baseAddress, $0.count, &width, &height) })
        return try checkedSize(Int(width), Int(height))
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        // jxrlib decodes past the end of the data without complaint, so a short file could claim a gigabyte.
        // A flat grey image compresses to ~1 byte per 512 pixels with jxrlib; ask for an eighth of that.
        let (claimedWidth, claimedHeight) = try size(data)
        guard data.count >= claimedWidth * claimedHeight / 4096 else { throw OwnDecodeError.truncated }
        var pixels: UnsafeMutablePointer<UInt8>?
        var width: Int32 = 0, height: Int32 = 0, channels: Int32 = 0, premultiplied: Int32 = 0, stride = 0
        try check(data.withUnsafeBytes {
            // The decode buffer may hold up to 16 bytes per pixel (128-bit float) before conversion.
            fv_jxr_decode($0.baseAddress, $0.count, 4 << 30, &pixels, &width, &height, &channels, &premultiplied, &stride)
        })
        guard let pixels else { throw OwnDecodeError.corrupt }
        defer { free(pixels) }
        let (w, h) = try checkedSize(Int(width), Int(height))
        let n = Int(channels)
        var out = [UInt8](repeating: 255, count: w * h * 4)
        out.withUnsafeMutableBufferPointer { out in
            for y in 0..<h {
                let row = pixels + y * stride
                for x in 0..<w {
                    let s = row + x * n, d = (y * w + x) * 4
                    if n == 1 {
                        out[d] = s[0]; out[d + 1] = s[0]; out[d + 2] = s[0]
                    } else {
                        out[d] = s[0]; out[d + 1] = s[1]; out[d + 2] = s[2]
                        if n == 4 {
                            let alpha = Int(s[3])
                            out[d + 3] = s[3]
                            if premultiplied != 0, alpha > 0, alpha < 255 {
                                for c in 0..<3 { out[d + c] = UInt8(min(255, (Int(s[c]) * 255 + alpha / 2) / alpha)) }
                            }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    private static func check(_ result: Int32) throws {
        switch Int(result) {
        case FVJXR_OK: return
        case FVJXR_NOT_JXR: throw OwnDecodeError.notThisFormat
        case FVJXR_UNSUPPORTED, FVJXR_TOO_BIG: throw OwnDecodeError.unsupported
        default: throw OwnDecodeError.corrupt
        }
    }
}
