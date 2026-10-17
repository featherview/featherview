import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Batch "Colour" step: values act on the sRGB-encoded values the user sees (the render context works
/// in sRGB), results clamped to 0…1, alpha untouched. Reducing colours is the pixels step after the render.
public enum ColourStep {
    public static func apply(_ image: CIImage, _ s: ColourSettings, scale: Double) -> CIImage {
        guard s.isOn else { return image }
        var image = image
        if s.autoAdjust {
            // The analysis gives a black-making curve for one-pixel-wide images: measure a copy widened by
            // repeating the edge (same colours, same histogram) and apply the result to the image itself.
            var measured = image.extent
            measured.size.width = max(2, measured.width)
            let analysed = image.clampedToExtent().cropped(to: measured)
            for filter in analysed.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(image, forKey: kCIInputImageKey)
                image = filter.outputImage ?? image
            }
        }
        if s.greyscale {
            let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            image = colourMatrix(image, r: luma, g: luma, b: luma)
        }
        if s.negative {
            let f = CIFilter.colorInvert()
            f.inputImage = image
            image = f.outputImage!
        }
        if s.brightness != 0 {
            let b = Double(s.brightness) / 255
            image = colourMatrix(image, bias: CIVector(x: b, y: b, z: b, w: 0))
        }
        if s.contrast != 0 {
            let m = 1 + Double(s.contrast) / 127, bias = 0.5 * (1 - m)
            image = colourMatrix(image, r: CIVector(x: m, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: m, z: 0, w: 0),
                                 b: CIVector(x: 0, y: 0, z: m, w: 0), bias: CIVector(x: bias, y: bias, z: bias, w: 0))
        }
        if s.gamma != 1, s.gamma > 0 {
            let f = CIFilter.gammaAdjust()
            f.inputImage = image
            f.power = Float(1 / s.gamma)
            image = clamped(f.outputImage!)
        }
        if s.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.saturation = Float(1 + Double(s.saturation) / 255)
            image = clamped(f.outputImage!)
        }
        if s.balanceRed != 0 || s.balanceGreen != 0 || s.balanceBlue != 0 {
            image = colourMatrix(image, bias: CIVector(x: Double(s.balanceRed) / 255, y: Double(s.balanceGreen) / 255,
                                                       z: Double(s.balanceBlue) / 255, w: 0))
        }
        if s.sharpen > 0 {
            image = edgeSafe(image) { input in
                let f = CIFilter.sharpenLuminance()
                f.inputImage = input
                f.sharpness = Float(Double(s.sharpen) / 25)
                f.radius = Float(1.5 * scale)
                return f.outputImage!
            }
        }
        if s.blur > 0 {
            image = edgeSafe(image) { input in
                let f = CIFilter.gaussianBlur()
                f.inputImage = input
                f.radius = Float(Double(s.blur) / 4 * scale)
                return f.outputImage!
            }
        }
        return image
    }
}

/// Batch "Filters" step, in spec order: auto levels, noise reduction, unsharp mask, colour temperature, sepia.
public enum FilterStep {
    public static func apply(_ image: CIImage, _ s: FilterSettings, scale: Double) -> CIImage {
        guard s.isOn else { return image }
        var image = image
        if s.autoLevels { image = autoLevels(image) }
        if s.noiseReduction > 0 {
            image = edgeSafe(image) { input in
                let f = CIFilter.noiseReduction()
                f.inputImage = input
                f.noiseLevel = Float(Double(s.noiseReduction) / 1000)
                f.sharpness = 0.4
                return f.outputImage!
            }
        }
        if s.unsharpMask > 0 {
            image = edgeSafe(image) { input in
                let f = CIFilter.unsharpMask()
                f.inputImage = input
                f.radius = Float(2.5 * scale)
                f.intensity = Float(Double(s.unsharpMask) / 50)
                return f.outputImage!
            }
        }
        if s.colourTemperature != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - 30 * CGFloat(s.colourTemperature), y: 0)
            image = clamped(f.outputImage!)
        }
        if s.sepia > 0 {
            let f = CIFilter.sepiaTone()
            f.inputImage = image
            f.intensity = Float(Double(s.sepia) / 100)
            image = f.outputImage!
        }
        return image
    }

    /// Per colour channel, the 0.5 % and 99.5 % points of a 256-bin histogram stretched to 0 and 1.
    static func autoLevels(_ image: CIImage) -> CIImage {
        let bins = 256
        let f = CIFilter.areaHistogram()
        f.inputImage = image.unpremultiplyingAlpha() // the stretch acts on straight colours, so measure those
        f.extent = image.extent
        f.count = bins
        f.scale = 1
        guard let histogram = f.outputImage else { return image }
        var counts = [Float](repeating: 0, count: bins * 4)
        counts.withUnsafeMutableBytes { buffer in
            PipelineRender.context.render(histogram, toBitmap: buffer.baseAddress!, rowBytes: bins * 16,
                                          bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        }
        var scales = [CGFloat](repeating: 1, count: 3), biases = [CGFloat](repeating: 0, count: 3)
        for channel in 0..<3 {
            var column = (0..<bins).map { counts[$0 * 4 + channel] }
            column[0] = max(0, column[0] - counts[3]) // transparent pixels (alpha bin 0) are no colour, not black
            let total = column.reduce(0, +)
            guard total > 0 else { continue }
            var sum: Float = 0, low = -1, high = -1
            for (bin, count) in column.enumerated() {
                sum += count
                if low < 0, sum >= total * 0.005 { low = bin }
                if high < 0, sum >= total * 0.995 { high = bin; break }
            }
            guard low >= 0, high > low else { continue }
            let lo = CGFloat(low) / CGFloat(bins - 1), hi = CGFloat(high) / CGFloat(bins - 1)
            scales[channel] = 1 / (hi - lo)
            biases[channel] = -lo / (hi - lo)
        }
        guard scales != [1, 1, 1] else { return image }
        return colourMatrix(image, r: CIVector(x: scales[0], y: 0, z: 0, w: 0), g: CIVector(x: 0, y: scales[1], z: 0, w: 0),
                            b: CIVector(x: 0, y: 0, z: scales[2], w: 0),
                            bias: CIVector(x: biases[0], y: biases[1], z: biases[2], w: 0))
    }
}

private func colourMatrix(_ image: CIImage, r: CIVector = CIVector(x: 1, y: 0, z: 0, w: 0),
                          g: CIVector = CIVector(x: 0, y: 1, z: 0, w: 0), b: CIVector = CIVector(x: 0, y: 0, z: 1, w: 0),
                          bias: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
    let f = CIFilter.colorMatrix()
    f.inputImage = image
    f.rVector = r
    f.gVector = g
    f.bVector = b
    f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    f.biasVector = bias
    return clamped(f.outputImage!)
}

private func clamped(_ image: CIImage) -> CIImage {
    let f = CIFilter.colorClamp()
    f.inputImage = image
    return f.outputImage!
}

/// Neighbourhood filters read past the edges: feed them the clamped-to-extent image and crop back,
/// so edges don't darken.
private func edgeSafe(_ image: CIImage, _ filter: (CIImage) -> CIImage) -> CIImage {
    filter(image.clampedToExtent()).cropped(to: image.extent)
}
