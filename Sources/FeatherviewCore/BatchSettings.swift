import CoreGraphics
import Foundation

// Everything the batch window sets (spec "Batch window"), in one value the window edits, presets
// store and the converter reads. Numeric ranges in comments are the valid ranges: steps clamp
// values when they use them, never trust them. Decoding tolerates missing or wrong-typed keys
// (presets outlive app versions): each falls back to its default.

public enum BatchMode: String, Codable, Sendable, CaseIterable { case convert, rename, convertAndRename }

/// A position in the picture (not in the UI: it never mirrors).
public enum ImageAnchor: String, Codable, Sendable, CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
}

/// sRGB, 0…1, straight alpha.
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

public struct CropSettings: Codable, Equatable, Sendable {
    public var isOn = false
    /// Pixels; width/height 0 = to the edge.
    public var x = 0, y = 0, width = 0, height = 0
    public var anchor = ImageAnchor.topLeft
    public init() {}
}

public enum ResizeMode: String, Codable, Sendable, CaseIterable { case widthHeight, longestSide, shortestSide, megapixels, percent }

public struct ResizeSettings: Codable, Equatable, Sendable {
    public var isOn = false
    public var mode = ResizeMode.longestSide
    public var width: Int?
    public var height: Int?
    public var side = 1920
    public var megapixels = 12.0
    public var percentWidth = 50.0
    public var percentHeight = 50.0
    public var keepAspect = true
    public var dontEnlarge = true
    public var dontShrink = false
    public var dpi: Int?
    public init() {}
}

public enum QuarterTurn: String, Codable, Sendable { case none, left, right }

public struct OrientationSettings: Codable, Equatable, Sendable {
    public var rotate = QuarterTurn.none
    public var flipHorizontal = false
    public var flipVertical = false
    public init() {}
    public var isOn: Bool { rotate != .none || flipHorizontal || flipVertical }
}

public struct ColourSettings: Codable, Equatable, Sendable {
    public var isOn = false
    public var greyscale = false
    public var negative = false
    public var autoAdjust = false
    /// −255…255
    public var brightness = 0
    /// −127…127
    public var contrast = 0
    /// 0.01…6.99
    public var gamma = 1.0
    /// −255…255
    public var saturation = 0
    /// −255…255 each
    public var balanceRed = 0, balanceGreen = 0, balanceBlue = 0
    /// 0…99 each
    public var sharpen = 0, blur = 0
    /// 2…256; nil = keep the depth.
    public var reduceColours: Int?
    public var dither = true
    public init() {}
}

public struct FilterSettings: Codable, Equatable, Sendable {
    public var isOn = false
    /// 0…100, 0 = off.
    public var unsharpMask = 0, noiseReduction = 0, sepia = 0
    /// −100…100, + = warmer, 0 = off.
    public var colourTemperature = 0
    public var autoLevels = false
    public init() {}
}

public enum CanvasMethod: String, Codable, Sendable, CaseIterable { case perSide, totalSize, aspectRatio }

public struct CanvasSettings: Codable, Equatable, Sendable {
    public var isOn = false
    public var autoCropBorders = false
    public var method = CanvasMethod.perSide
    /// Pixels, may be negative.
    public var left = 10, right = 10, top = 10, bottom = 10
    /// Pixels, 0 = keep that side.
    public var width = 1920, height = 1080
    public var ratioWidth = 1.0, ratioHeight = 1.0
    public var anchor = ImageAnchor.center
    public var colour = RGBAColor.black
    public init() {}
}

public struct BorderSettings: Codable, Equatable, Sendable {
    public var isOn = false
    /// Pixels.
    public var outerWidth = 10
    public var outerColour = RGBAColor.white
    /// Pixels; 0 = one border.
    public var innerWidth = 0
    public var innerColour = RGBAColor.black
    public init() {}
}

public enum TextPlacement: String, Codable, Sendable, CaseIterable { case inImage, stripBelow, stripAbove }

public struct TextSettings: Codable, Equatable, Sendable {
    public var isOn = false
    public var text = "{name}"
    /// PostScript name.
    public var fontName = "Helvetica-Bold"
    /// Of the shorter side, 0.5…50.
    public var sizePercent = 3.0
    public var colour = RGBAColor.white
    public var position = ImageAnchor.bottomRight
    /// 0…25
    public var marginPercent = 2.0
    public var placement = TextPlacement.inImage
    /// 0…1
    public var opacity = 1.0
    public var shadow = true
    public var backgroundBox = false
    public var boxColour = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
    public init() {}
}

public struct WatermarkSettings: Codable, Equatable, Sendable {
    public var isOn = false
    /// The app isn't sandboxed: a plain path.
    public var path = ""
    public var position = ImageAnchor.bottomRight
    public var marginPercent = 2.0
    /// Of the output's width, 1…100.
    public var widthPercent = 20.0
    public var opacity = 0.33
    public init() {}
}

public struct SafetySettings: Codable, Equatable, Sendable {
    public var replaceExisting = false
    public var trashOriginals = false
    public var keepDates = false
    public var recreateSubfolders = false

    public init(replaceExisting: Bool = false, trashOriginals: Bool = false, keepDates: Bool = false,
                recreateSubfolders: Bool = false) {
        self.replaceExisting = replaceExisting; self.trashOriginals = trashOriginals
        self.keepDates = keepDates; self.recreateSubfolders = recreateSubfolders
    }
}

public struct BatchSettings: Codable, Equatable, Sendable {
    public var mode = BatchMode.convert
    public var formatID = "jpg"
    public var options = FormatOptions()
    /// A path; may contain {folder}.
    public var outputFolder = ""
    public var renamePattern = "{name}"
    public var crop = CropSettings(), resize = ResizeSettings(), orientation = OrientationSettings()
    public var colour = ColourSettings(), filters = FilterSettings(), canvas = CanvasSettings()
    public var border = BorderSettings(), text = TextSettings(), watermark = WatermarkSettings()
    public var safety = SafetySettings()

    public init() {}

    /// The output format, or JPEG when this Mac can't write the stored one.
    public var format: OutputFormat { FormatRegistry.format(id: formatID) ?? .jpeg }

    /// Switches to another format with its saved options; picking the current one keeps the options.
    public mutating func setFormat(_ new: OutputFormat, in defaults: UserDefaults = .standard) {
        guard new.id != format.id else { return }
        formatID = new.id
        options = FormatSettings.options(for: new, in: defaults)
    }

    /// True when no operation is on: the converter may take the fast path.
    public var hasOperations: Bool {
        crop.isOn || resize.isOn || orientation.isOn || colour.isOn || filters.isOn || canvas.isOn
            || border.isOn || text.isOn || watermark.isOn
    }
}

/// One file of the batch's input list.
public struct BatchInput: Hashable, Sendable {
    public let url: URL
    /// The folder the user added (with or without subfolders); nil for files added one by one.
    /// "Recreate subfolders" and `{folder}` use it.
    public let root: URL?

    public init(url: URL, root: URL? = nil) {
        self.url = url
        self.root = root
    }

    /// The image's size in bytes (through a symlink, not the link's own), 0 when it can't be read.
    public func fileSize() -> Int {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

// MARK: - Tolerant decoding

private extension KeyedDecodingContainer {
    /// The stored value, or `fallback` when it's missing or of the wrong type.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

extension RGBAColor {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(red: c.value(.red, 0), green: c.value(.green, 0), blue: c.value(.blue, 0), alpha: c.value(.alpha, 1))
    }
}

extension CropSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        x = c.value(.x, d.x); y = c.value(.y, d.y)
        width = c.value(.width, d.width); height = c.value(.height, d.height)
        anchor = c.value(.anchor, d.anchor)
    }
}

extension ResizeSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        mode = c.value(.mode, d.mode)
        width = c.value(.width, d.width); height = c.value(.height, d.height)
        side = c.value(.side, d.side)
        megapixels = c.value(.megapixels, d.megapixels)
        percentWidth = c.value(.percentWidth, d.percentWidth); percentHeight = c.value(.percentHeight, d.percentHeight)
        keepAspect = c.value(.keepAspect, d.keepAspect)
        dontEnlarge = c.value(.dontEnlarge, d.dontEnlarge); dontShrink = c.value(.dontShrink, d.dontShrink)
        dpi = c.value(.dpi, d.dpi)
    }
}

extension OrientationSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        rotate = c.value(.rotate, d.rotate)
        flipHorizontal = c.value(.flipHorizontal, d.flipHorizontal)
        flipVertical = c.value(.flipVertical, d.flipVertical)
    }
}

extension ColourSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        greyscale = c.value(.greyscale, d.greyscale); negative = c.value(.negative, d.negative)
        autoAdjust = c.value(.autoAdjust, d.autoAdjust)
        brightness = c.value(.brightness, d.brightness); contrast = c.value(.contrast, d.contrast)
        gamma = c.value(.gamma, d.gamma); saturation = c.value(.saturation, d.saturation)
        balanceRed = c.value(.balanceRed, d.balanceRed); balanceGreen = c.value(.balanceGreen, d.balanceGreen)
        balanceBlue = c.value(.balanceBlue, d.balanceBlue)
        sharpen = c.value(.sharpen, d.sharpen); blur = c.value(.blur, d.blur)
        reduceColours = c.value(.reduceColours, d.reduceColours); dither = c.value(.dither, d.dither)
    }
}

extension FilterSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        unsharpMask = c.value(.unsharpMask, d.unsharpMask); noiseReduction = c.value(.noiseReduction, d.noiseReduction)
        sepia = c.value(.sepia, d.sepia); colourTemperature = c.value(.colourTemperature, d.colourTemperature)
        autoLevels = c.value(.autoLevels, d.autoLevels)
    }
}

extension CanvasSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        autoCropBorders = c.value(.autoCropBorders, d.autoCropBorders)
        method = c.value(.method, d.method)
        left = c.value(.left, d.left); right = c.value(.right, d.right)
        top = c.value(.top, d.top); bottom = c.value(.bottom, d.bottom)
        width = c.value(.width, d.width); height = c.value(.height, d.height)
        ratioWidth = c.value(.ratioWidth, d.ratioWidth); ratioHeight = c.value(.ratioHeight, d.ratioHeight)
        anchor = c.value(.anchor, d.anchor); colour = c.value(.colour, d.colour)
    }
}

extension BorderSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        outerWidth = c.value(.outerWidth, d.outerWidth); outerColour = c.value(.outerColour, d.outerColour)
        innerWidth = c.value(.innerWidth, d.innerWidth); innerColour = c.value(.innerColour, d.innerColour)
    }
}

extension TextSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        text = c.value(.text, d.text); fontName = c.value(.fontName, d.fontName)
        sizePercent = c.value(.sizePercent, d.sizePercent); colour = c.value(.colour, d.colour)
        position = c.value(.position, d.position); marginPercent = c.value(.marginPercent, d.marginPercent)
        placement = c.value(.placement, d.placement); opacity = c.value(.opacity, d.opacity)
        shadow = c.value(.shadow, d.shadow); backgroundBox = c.value(.backgroundBox, d.backgroundBox)
        boxColour = c.value(.boxColour, d.boxColour)
    }
}

extension WatermarkSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        isOn = c.value(.isOn, d.isOn)
        path = c.value(.path, d.path); position = c.value(.position, d.position)
        marginPercent = c.value(.marginPercent, d.marginPercent); widthPercent = c.value(.widthPercent, d.widthPercent)
        opacity = c.value(.opacity, d.opacity)
    }
}

extension SafetySettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        self.init(replaceExisting: c.value(.replaceExisting, d.replaceExisting),
                  trashOriginals: c.value(.trashOriginals, d.trashOriginals),
                  keepDates: c.value(.keepDates, d.keepDates),
                  recreateSubfolders: c.value(.recreateSubfolders, d.recreateSubfolders))
    }
}

extension BatchSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        mode = c.value(.mode, d.mode)
        formatID = c.value(.formatID, d.formatID)
        options = c.value(.options, d.options)
        outputFolder = c.value(.outputFolder, d.outputFolder)
        renamePattern = c.value(.renamePattern, d.renamePattern)
        crop = c.value(.crop, d.crop); resize = c.value(.resize, d.resize)
        orientation = c.value(.orientation, d.orientation); colour = c.value(.colour, d.colour)
        filters = c.value(.filters, d.filters); canvas = c.value(.canvas, d.canvas)
        border = c.value(.border, d.border); text = c.value(.text, d.text)
        watermark = c.value(.watermark, d.watermark); safety = c.value(.safety, d.safety)
    }
}
