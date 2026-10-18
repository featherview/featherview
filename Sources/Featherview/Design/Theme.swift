import AppKit
import FeatherviewCore
import SwiftUI

/// The design tokens of the viewer chrome (docs/DESIGN.md, from the design canvas). Every colour, shadow,
/// radius, size and duration the views use comes from here; values that fit's arithmetic needs live in
/// `CanvasInsets` (FeatherviewCore, tested) and are named here too.
/// Colours carry a dark (Graphite) and a light (Grey) value and resolve by the window's appearance,
/// which follows the background colour (`Theme.isDark(background:)`).
enum Theme {
    // MARK: Appearance

    /// Luminance below ½ → dark tokens, else light (spec "Custom background").
    static func isDark(background hex: String) -> Bool { HexColor.isDark(hex) }

    /// The appearance a viewer window takes on this background: always set, so a light background in
    /// system dark mode still gets the light tokens.
    static func appearance(background hex: String) -> NSAppearance? {
        NSAppearance(named: isDark(background: hex) ? .darkAqua : .aqua)
    }

    // MARK: Colours

    /// One colour token: its dark and light value, resolved by the effective appearance.
    static func colour(dark: NSColor, light: NSColor) -> Color { Color(nsColor: dynamic(dark: dark, light: light)) }

    /// The same, for AppKit and Core Animation (resolve a CGColor inside the view's appearance).
    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    /// Background · Graphite, the default (dark).
    static let graphite = BackgroundPreset.graphite.hex
    /// Background · Grey (light).
    static let grey = BackgroundPreset.grey.hex

    /// Glass fill: toolbar groups, status strip, empty hint card (macOS 14/15 tint over the material).
    static let glassFill = colour(dark: rgb(52, 52, 58, 0.55), light: white(0.60))
    /// Glass fill · panel: the info panel, laid over the material at `panelFillOpacity`.
    static let panelFill = colour(dark: rgb(44, 44, 50, 0.62), light: white(0.66))
    /// Glass fill · sheet: folder chooser, Move/Copy to Folder, laid over the material at `sheetFillOpacity`.
    static let sheetFill = colour(dark: rgb(36, 36, 42, 0.66), light: white(0.72))
    static let panelFillOpacity = 0.25
    static let sheetFillOpacity = 0.35
    /// Glass highlight: 1 pt light along the top edge, inset (macOS 14/15 only; the glass draws its own on 26).
    static let glassHighlight = colour(dark: white(0.12), light: white(0.70))
    /// Glass hairline: 1 pt inset outline of the shape (macOS 14/15 only).
    static let glassHairline = colour(dark: white(0.06), light: black(0.06))
    /// Picture hairline: 1 pt, with the E3 shadow, only while the picture fits.
    static let pictureHairline = dynamic(dark: white(0.06), light: black(0.08))

    /// Label · primary: title, row labels, glyphs.
    static let labelPrimary = colour(dark: white(0.85), light: black(0.85))
    /// Label · primary (0.90): panel and sheet titles.
    static let labelTitle = colour(dark: white(0.90), light: black(0.90))
    /// Label · secondary: counter in the title, values, counts.
    static let labelSecondary = colour(dark: white(0.55), light: black(0.55))
    /// Label · strip: status strip text.
    static let labelStrip = colour(dark: white(0.70), light: black(0.65))
    /// Empty-window hint text (secondary 0.70).
    static let labelHint = colour(dark: white(0.70), light: black(0.65))
    /// Label · tertiary: "Empty", footer hints, "end of folder".
    static let labelTertiary = colour(dark: white(0.40), light: black(0.40))
    /// Disabled glyph: back/forward at either end, the whole toolbar in the empty window.
    static let disabledGlyph = colour(dark: white(0.30), light: black(0.25))
    /// Separator: 1 pt dividers inside capsules.
    static let separator = colour(dark: white(0.14), light: black(0.12))
    /// Separator in the status strip.
    static let stripSeparator = colour(dark: white(0.16), light: black(0.12))
    /// Row separators inside cards.
    static let rowSeparator = colour(dark: white(0.10), light: black(0.08))

    /// Key cap fill, line and text.
    static let keyCapFill = colour(dark: white(0.07), light: black(0.05))
    static let keyCapLine = colour(dark: white(0.14), light: black(0.12))
    static let keyCapText = colour(dark: white(0.70), light: black(0.60))
    /// Key cap and small button on an accent (selected) row.
    static let onAccentKeyFill = Color.white.opacity(0.22)
    static let onAccentButtonFill = Color.white.opacity(0.20)
    /// Count on an accent row.
    static let onAccentSecondary = Color.white.opacity(0.75)

    /// Toggled pill: behind an active toolbar item (Info while the panel is open).
    static let toggledPill = colour(dark: white(0.12), light: black(0.08))
    /// Toolbar item hover and pressed backgrounds.
    static let itemHover = colour(dark: white(0.08), light: black(0.05))
    static let itemPressed = colour(dark: white(0.14), light: black(0.09))

    /// Info panel: format badge fill and line; grouped-rows card fill and line.
    static let badgeFill = colour(dark: white(0.08), light: black(0.08))
    static let badgeLine = colour(dark: white(0.12), light: black(0.12))
    static let cardFill = colour(dark: white(0.04), light: black(0.04))
    static let cardLine = colour(dark: white(0.06), light: black(0.06))

    /// Preferences tab pill, selected.
    static let tabPill = colour(dark: white(0.10), light: black(0.07))

    /// Accent: selections and toggled glyphs. Never the feather colours.
    static let accent = Color.accentColor

    /// Feather mark: #FFC766 → #FF7A59, top-leading to bottom-trailing. Only the empty hint and About.
    static let featherStart = rgb(0xFF, 0xC7, 0x66, 1)
    static let featherEnd = rgb(0xFF, 0x7A, 0x59, 1)
    static let featherGradient = LinearGradient(colors: [Color(nsColor: featherStart), Color(nsColor: featherEnd)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)

    /// About: the icon tile's gradient, and the feather glow behind it (dark 0.26, light 0.45 → 0).
    static let aboutTile = LinearGradient(colors: [Color(nsColor: rgb(0x23, 0x23, 0x2C, 1)), Color(nsColor: rgb(0x10, 0x10, 0x15, 1))],
                                          startPoint: .top, endPoint: .bottom)
    static let aboutGlowStart = colour(dark: featherStart.withAlphaComponent(0.26), light: featherStart.withAlphaComponent(0.45))
    static let aboutGlowMid = colour(dark: featherEnd.withAlphaComponent(0.12), light: featherEnd.withAlphaComponent(0.2))
    static let aboutGlowSize = 280.0

    // MARK: Elevation

    /// One shadow layer; `blur` as in the spec (CSS), `alpha` per appearance. Always neutral black.
    struct ShadowLayer: Sendable {
        let y: CGFloat
        let blur: CGFloat
        let dark: CGFloat
        let light: CGFloat
        var colour: Color { Theme.colour(dark: Theme.black(dark), light: Theme.black(light)) }
        /// SwiftUI's radius is about half a CSS blur.
        var radius: CGFloat { blur / 2 }
    }

    /// Elevation E0–E5: a tight contact shadow and a wide ambient one; only the alpha changes per appearance.
    struct Elevation: Sendable {
        let layers: [ShadowLayer]

        /// Flat: key caps, selected rows, toggled pills, badges, separators.
        static let e0 = Elevation(layers: [])
        /// Raised control: switch knobs, light push buttons and pop-ups.
        static let e1 = Elevation(layers: [ShadowLayer(y: 1, blur: 3, dark: 0.30, light: 0.12)])
        /// Floating chrome: toolbar groups, status strip.
        static let e2 = Elevation(layers: [ShadowLayer(y: 1, blur: 2, dark: 0.20, light: 0.06),
                                           ShadowLayer(y: 6, blur: 16, dark: 0.30, light: 0.10)])
        /// Surface in the window: fitted picture, info panel, empty hint card.
        static let e3 = Elevation(layers: [ShadowLayer(y: 2, blur: 4, dark: 0.22, light: 0.07),
                                           ShadowLayer(y: 12, blur: 32, dark: 0.34, light: 0.14)])
        /// Sheet: folder chooser, Move to Folder, the About icon tile.
        static let e4 = Elevation(layers: [ShadowLayer(y: 4, blur: 8, dark: 0.26, light: 0.08),
                                           ShadowLayer(y: 20, blur: 48, dark: 0.40, light: 0.18)])
        /// Window: documents the mockups only; the system draws window shadows.
        static let e5 = Elevation(layers: [ShadowLayer(y: 8, blur: 16, dark: 0.28, light: 0.10),
                                           ShadowLayer(y: 32, blur: 72, dark: 0.45, light: 0.22)])
    }

    // MARK: Typography (SF Pro; tabular where numbers change in place)

    /// Window title: 13 Semibold.
    static let windowTitle = Font.system(size: 13, weight: .semibold)
    /// Title counter " — n / N": 13 Regular, tabular.
    static let counter = Font.system(size: 13).monospacedDigit()
    /// Status strip: 11 Regular, tabular.
    static let strip = Font.system(size: 11).monospacedDigit()
    /// Key cap: 11 Medium.
    static let keyCap = Font.system(size: 11, weight: .medium)
    /// F7 slot key: 12 Semibold, tabular, in a 22 × 22 square.
    static let slotKey = Font.system(size: 12, weight: .semibold).monospacedDigit()
    /// Panel / sheet title: 15 Semibold.
    static let panelTitle = Font.system(size: 15, weight: .semibold)
    /// Info panel header (file name): 13 Semibold.
    static let panelHeader = Font.system(size: 13, weight: .semibold)
    /// Row label 13 Regular; Medium on a selected row.
    static let row = Font.system(size: 13)
    static let rowSelected = Font.system(size: 13, weight: .medium)
    /// Row value / count: 13 Regular, tabular.
    static let rowValue = Font.system(size: 13).monospacedDigit()
    /// Empty-window hint: 13 Regular.
    static let hintText = Font.system(size: 13)
    /// Hint / caption: 11 Regular (footers, "end of folder").
    static let hint = Font.system(size: 11)
    /// Format badge: 11 Medium.
    static let badge = Font.system(size: 11, weight: .medium)
    /// Error and "No images" message boxes' padding (spec silent: kept from before).
    static let messagePadding = 8.0
    /// Small button ("Choose…"): 12 Medium.
    static let smallButton = Font.system(size: 12, weight: .medium)
    /// About: name 22 Semibold, tagline 13, small print 11.
    static let aboutName = Font.system(size: 22, weight: .semibold)
    static let aboutTagline = Font.system(size: 13)
    static let aboutSmall = Font.system(size: 11)
    static let aboutVersion = Font.system(size: 11, weight: .medium).monospacedDigit()
    /// Toolbar glyphs: 15 Medium; back/forward 13 Semibold.
    static let toolbarGlyph = Font.system(size: 15, weight: .medium)
    static let chevronGlyph = Font.system(size: 13, weight: .semibold)
    /// Glyph in chooser rows and header: 16.
    static let rowGlyph = Font.system(size: 16)

    // MARK: Metrics (pt)

    /// Title bar height (the unified toolbar on macOS 26).
    static let titleBarHeight = 52.0
    /// Fit-area insets: leading, top, trailing, bottom (bottom = strip 28 + 8 inset + 8 clearance).
    static let fitInsets = EdgeInsets(top: 60, leading: CanvasInsets.side, bottom: 44, trailing: CanvasInsets.side)
    /// Toolbar capsules and their items.
    static let leadingGroup = CGSize(width: 76, height: 32)
    static let trailingGroup = CGSize(width: 256, height: 32)
    static let toolbarItem = CGSize(width: 36, height: 28)
    static let toolbarSeparator = CGSize(width: 1, height: 16)
    /// Status strip: 28 tall, 12 side and 8 bottom inset, 14 inner padding, 12 between items, 1 × 12 separators.
    static let stripHeight = CanvasInsets.stripHeight
    static let stripSideInset = CanvasInsets.stripSideMargin
    static let stripBottomInset = CanvasInsets.stripMargin
    static let stripPadding = 14.0
    static let stripGap = 12.0
    static let stripSeparatorHeight = 12.0
    /// Info panel width, its inset from the trailing edge, and its padding / gap.
    static let infoPanelWidth = 280.0
    static let infoPanelInset = 12.0
    static let panelPadding = 16.0
    static let panelGap = 12.0
    static let infoHeaderHeight = 24.0
    static let infoRowHeight = 40.0
    /// Sheet widths.
    static let chooserWidth = 400.0
    static let moveSheetWidth = 480.0
    static let sheetHeaderHeight = 20.0
    static let chooserRowHeight = 40.0
    static let moveRowHeight = 32.0
    static let rowGap = 10.0
    /// Empty hint card.
    static let emptyCard = CGSize(width: 300, height: 168)
    static let emptyCardPadding = EdgeInsets(top: 24, leading: 28, bottom: 24, trailing: 28)
    static let emptyCardGap = 12.0
    static let featherSize = 44.0
    /// Key caps: auto × 20, padding 3 × 7; footer caps padding 1 × 5; F7 slot keys 22 × 22.
    static let keyCapPadding = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
    static let footerKeyCapPadding = EdgeInsets(top: 1, leading: 5, bottom: 1, trailing: 5)
    static let slotKeySize = 22.0
    static let keyCapGap = 6.0
    /// Small button ("Choose…"): 22 tall, 10 side padding.
    static let smallButtonHeight = 22.0
    static let smallButtonPadding = 10.0

    /// Corner radii, from the outside in.
    enum Radius {
        /// Empty hint card.
        static let card = 18.0
        /// Info panel, chooser, F7 sheet; toolbar capsules are 16 = half their height.
        static let panel = 16.0
        /// Toolbar items, toggled pill, strip (half of 28).
        static let item = 14.0
        /// Preferences cards, grouped rows in the info panel.
        static let group = 10.0
        /// Chooser rows.
        static let chooserRow = 9.0
        /// F7 rows.
        static let moveRow = 8.0
        /// Push buttons.
        static let pushButton = 7.0
        /// F7 slot key, small button.
        static let slotKey = 6.0
        /// Key cap.
        static let keyCap = 5.0
        /// Footer key cap, format badge, pop-up chevron square.
        static let small = 4.0
        /// Error and "No images" message boxes (spec silent: the size they had before the design).
        static let message = 6.0
        /// About icon tile.
        static let aboutTile = 28.8
    }

    // MARK: Motion

    enum Motion {
        /// Hover and press fill change.
        static let hover = 0.08
        /// Zoom step (keyboard, buttons, Fit), ease-out, about the cursor; pinch: none.
        static let zoom = 0.12
        /// Rotation, ease-in-out, about the picture centre.
        static let rotation = 0.16
        /// Info panel slide (24 pt from the trailing edge) and fade, with the picture refit; ease-in-out.
        static let panel = 0.18
        static let panelTravel = 24.0
        /// Sheets: in 160 ms (scale 0.97 → 1 + fade), out 120 ms.
        static let sheetIn = 0.16
        static let sheetOut = 0.12
        static let sheetScale = 0.97
        /// Move / Trash: the leaving picture fades out.
        static let leave = 0.06
        /// Bars at rest: after 2 s, out in 200 ms, back in 120 ms; opacity only.
        static let barsRest = BarsAutoHide.rest
        static let barsOut = 0.2
        static let barsIn = 0.12
        /// Strip text fade when a different file arrives; drop outline.
        static let stripFade = 0.12
        static let dropOutline = 0.12

        /// Reduce Motion: zoom, rotation, panels and sheets become 0; pure opacity changes keep their duration.
        static func duration(_ seconds: Double, reduceMotion: Bool, opacityOnly: Bool = false) -> Double {
            reduceMotion && !opacityOnly ? 0 : seconds
        }

        /// The SwiftUI animation for a movement, nil under Reduce Motion.
        static func moving(_ seconds: Double, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: seconds)
        }

        /// Things that arrive: ease-out, nil under Reduce Motion.
        static func arriving(_ seconds: Double, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: seconds)
        }

        /// Pure opacity: linear, kept under Reduce Motion.
        static func fade(_ seconds: Double) -> Animation { .linear(duration: seconds) }
    }
}

extension View {
    /// Applies an elevation level's contact and ambient shadows.
    func elevation(_ level: Theme.Elevation) -> some View { modifier(ElevationShadow(level: level)) }
}

private struct ElevationShadow: ViewModifier {
    let level: Theme.Elevation

    func body(content: Content) -> some View {
        if let contact = level.layers.first, let ambient = level.layers.last, level.layers.count == 2 {
            content.shadow(color: contact.colour, radius: contact.radius, y: contact.y)
                .shadow(color: ambient.colour, radius: ambient.radius, y: ambient.y)
        } else if let layer = level.layers.first {
            content.shadow(color: layer.colour, radius: layer.radius, y: layer.y)
        } else {
            content
        }
    }
}
