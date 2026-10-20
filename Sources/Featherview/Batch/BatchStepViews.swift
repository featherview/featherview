import AppKit
import FeatherviewCore
import SwiftUI

/// An open card's settings rows (spec "Window"), inside the card list's grouped form.
struct BatchCardBody: View {
    let card: BatchCard
    @Bindable var model: BatchModel

    var body: some View {
        switch card {
        case .format: FormatStep(model: model)
        case .size:
            Toggle("Change size", isOn: $model.settings.resize.isOn)
            if model.settings.resize.isOn { ResizeStepView(s: $model.settings.resize) }
        case .name:
            RenameStep(pattern: $model.settings.renamePattern)
            SaveToRow(folder: $model.settings.outputFolder)
            Text("Safety and dates")
                .font(Theme.badge)
                .foregroundStyle(Theme.labelSecondary)
            SafetyStep(s: $model.settings.safety)
        case .crop: CropStepView(s: $model.settings.crop)
        case .orientation: OrientationStepView(s: $model.settings.orientation)
        case .colour: ColourStepView(s: $model.settings.colour)
        case .filters: FiltersStepView(s: $model.settings.filters)
        case .canvas: CanvasStepView(s: $model.settings.canvas)
        case .border: BorderStepView(s: $model.settings.border)
        case .text: TextStepView(s: $model.settings.text)
        case .watermark: WatermarkStepView(s: $model.settings.watermark)
        }
    }
}

// MARK: - Format and name

private struct FormatStep: View {
    @Bindable var model: BatchModel
    @State private var showingOptions = false

    var body: some View {
        Toggle("Change format", isOn: $model.settings.changeFormat)
        if model.settings.changeFormat {
            LabeledContent("Format:") {
                Picker("Format:", selection: Binding { model.settings.format } set: { model.settings.setFormat($0) }) {
                    ForEach(FormatRegistry.writable) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Options…") { showingOptions = true }
            }
            .sheet(isPresented: $showingOptions) { optionsSheet }
        }
    }

    private var optionsSheet: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Form {
                Section("\(model.settings.format.name) Options") {
                    FormatOptionsView(format: model.settings.format, options: $model.settings.options)
                }
            }
            .formStyle(.grouped)
            Button("Done") { showingOptions = false }
                .keyboardShortcut(.defaultAction)
                .padding([.horizontal, .bottom])
        }
        .frame(width: 420)
    }
}

/// Empty = next to each original; clearing the field goes back to it.
private struct SaveToRow: View {
    @Binding var folder: String

    var body: some View {
        LabeledContent("Save to:") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Save to:", text: $folder, prompt: Text("Next to the originals"))
                        .labelsHidden()
                    Button("Choose…", action: chooseFolder)
                    // Back to the empty default without having to know that empty means this.
                    if !folder.isEmpty {
                        Button("Next to the originals") { folder = "" }
                    }
                }
                Text("{folder} in the path stands for each image's folder name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
    }
}

private struct RenameStep: View {
    @Binding var pattern: String

    var body: some View {
        LabeledContent("Pattern:") {
            TextField("Pattern:", text: $pattern)
                .labelsHidden()
                .frame(minWidth: 220)
        }
        LabeledContent("") {
            VStack(alignment: .leading, spacing: 6) {
                PlaceholderButtons(placeholders: ["{name}", "{n}", "{n:3}", "{date}"], text: $pattern)
                Text("The counter counts only the files that are converted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Appends a placeholder to a pattern.
private struct PlaceholderButtons: View {
    let placeholders: [String]
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(placeholders, id: \.self) { placeholder in
                Button(placeholder) { text += placeholder }
                    .font(.body.monospaced())
            }
        }
    }
}

// MARK: - Geometry

private struct CropStepView: View {
    @Binding var s: CropSettings

    var body: some View {
        IntRow("X:", $s.x, unit: "px")
        IntRow("Y:", $s.y, unit: "px")
        IntRow("Width:", $s.width, unit: "px", hint: "0 = to the edge")
        IntRow("Height:", $s.height, unit: "px", hint: "0 = to the edge")
        LabeledContent("From:") { AnchorPicker(anchor: $s.anchor) }
    }
}

private struct ResizeStepView: View {
    @Binding var s: ResizeSettings

    var body: some View {
        Picker("Resize to:", selection: $s.mode) {
            Text("Width and Height").tag(ResizeMode.widthHeight)
            Text("Longest Side").tag(ResizeMode.longestSide)
            Text("Shortest Side").tag(ResizeMode.shortestSide)
            Text("Megapixels").tag(ResizeMode.megapixels)
            Text("Percentage").tag(ResizeMode.percent)
        }
        .fixedSize()
        switch s.mode {
        case .widthHeight:
            OptionalIntRow("Width:", $s.width, unit: "px")
            OptionalIntRow("Height:", $s.height, unit: "px")
        case .longestSide, .shortestSide:
            IntRow("Side:", $s.side, unit: "px")
        case .megapixels:
            DoubleRow("Megapixels:", $s.megapixels, unit: "MP")
        case .percent:
            DoubleRow(s.keepAspect ? "Size:" : "Width:", $s.percentWidth, unit: "%")
            if !s.keepAspect { DoubleRow("Height:", $s.percentHeight, unit: "%") }
        }
        LabeledContent("") {
            VStack(alignment: .leading) {
                Toggle("Keep aspect ratio", isOn: $s.keepAspect)
                Toggle("Don't enlarge smaller images", isOn: $s.dontEnlarge)
                Toggle("Don't shrink larger images", isOn: $s.dontShrink)
            }
        }
        OptionalIntRow("DPI:", $s.dpi, unit: "", prompt: "Keep")
    }
}

private struct OrientationStepView: View {
    @Binding var s: OrientationSettings

    var body: some View {
        Picker("Rotate:", selection: $s.rotate) {
            Text("None").tag(QuarterTurn.none)
            Text("Left", comment: "Batch rotation: a quarter turn counter-clockwise").tag(QuarterTurn.left)
            Text("Right", comment: "Batch rotation: a quarter turn clockwise").tag(QuarterTurn.right)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        LabeledContent("Flip:") {
            VStack(alignment: .leading) {
                Toggle("Horizontally", isOn: $s.flipHorizontal)
                Toggle("Vertically", isOn: $s.flipVertical)
            }
        }
    }
}

// MARK: - Colour

private struct ColourStepView: View {
    @Binding var s: ColourSettings

    var body: some View {
        LabeledContent("") {
            VStack(alignment: .leading) {
                Toggle("Greyscale", isOn: $s.greyscale)
                Toggle("Negative", isOn: $s.negative)
                Toggle("Auto-adjust colours", isOn: $s.autoAdjust)
            }
        }
        SliderRow("Brightness:", $s.brightness, -255...255)
        SliderRow("Contrast:", $s.contrast, -127...127)
        LabeledContent("Gamma:") {
            Slider(value: $s.gamma, in: 0.01...6.99)
            TextField("Gamma:", value: $s.gamma, format: .number.precision(.fractionLength(2)))
                .labelsHidden()
                .frame(width: 56)
        }
        SliderRow("Saturation:", $s.saturation, -255...255)
        SliderRow("Red:", $s.balanceRed, -255...255)
        SliderRow("Green:", $s.balanceGreen, -255...255)
        SliderRow("Blue:", $s.balanceBlue, -255...255)
        SliderRow("Sharpen:", $s.sharpen, 0...99)
        SliderRow("Blur:", $s.blur, 0...99)
        LabeledContent {
            TextField("Colours", value: Binding { s.reduceColours ?? 256 } set: { s.reduceColours = min(max($0, 2), 256) },
                      format: .number)
                .labelsHidden()
                .frame(width: 56)
                .disabled(s.reduceColours == nil)
            Text("colours")
            Toggle("Dither", isOn: $s.dither)
                .disabled(s.reduceColours == nil)
        } label: {
            Toggle("Reduce to:", isOn: Binding { s.reduceColours != nil } set: { s.reduceColours = $0 ? 256 : nil })
        }
    }
}

private struct FiltersStepView: View {
    @Binding var s: FilterSettings

    var body: some View {
        SliderRow("Unsharp mask:", $s.unsharpMask, 0...100)
        SliderRow("Noise reduction:", $s.noiseReduction, 0...100)
        SliderRow("Sepia:", $s.sepia, 0...100)
        SliderRow("Colour temperature:", $s.colourTemperature, -100...100)
        Toggle("Auto levels", isOn: $s.autoLevels)
    }
}

// MARK: - Canvas, border, overlays

private struct CanvasStepView: View {
    @Binding var s: CanvasSettings

    /// Common ratios (spec "Canvas size"); √2 is the A paper sizes'.
    private static let ratios: [(name: String, width: Double, height: Double)] = [
        ("1:1", 1, 1), ("2:1", 2, 1), ("3:2", 3, 2), ("4:3", 4, 3), ("16:9", 16, 9), ("16:10", 16, 10), ("√2", 2.squareRoot(), 1),
    ]

    var body: some View {
        Toggle("Auto-crop uniform borders first", isOn: $s.autoCropBorders)
        Picker("Canvas:", selection: $s.method) {
            Text("Width per Side").tag(CanvasMethod.perSide)
            Text("Total Size").tag(CanvasMethod.totalSize)
            Text("Aspect Ratio").tag(CanvasMethod.aspectRatio)
        }
        .fixedSize()
        switch s.method {
        case .perSide:
            // Sides of the picture: they don't mirror.
            IntRow("Left:", $s.left, unit: "px")
            IntRow("Right:", $s.right, unit: "px")
            IntRow("Top:", $s.top, unit: "px")
            IntRow("Bottom:", $s.bottom, unit: "px", hint: "Negative values cut into the image")
        case .totalSize:
            IntRow("Width:", $s.width, unit: "px", hint: "0 = keep")
            IntRow("Height:", $s.height, unit: "px", hint: "0 = keep")
        case .aspectRatio:
            LabeledContent("Ratio:") {
                TextField("Width", value: $s.ratioWidth, format: .number.precision(.fractionLength(0...3)))
                    .labelsHidden()
                    .frame(width: 56)
                Text(verbatim: ":")
                TextField("Height", value: $s.ratioHeight, format: .number.precision(.fractionLength(0...3)))
                    .labelsHidden()
                    .frame(width: 56)
                Menu("Presets") {
                    ForEach(Self.ratios, id: \.name) { ratio in
                        Button(ratio.name) {
                            s.ratioWidth = ratio.width
                            s.ratioHeight = ratio.height
                        }
                    }
                }
                .fixedSize()
            }
        }
        if s.method != .perSide {
            LabeledContent("Place at:") { AnchorPicker(anchor: $s.anchor) }
        }
        ColourRow("Colour:", $s.colour)
    }
}

private struct BorderStepView: View {
    @Binding var s: BorderSettings

    var body: some View {
        LabeledContent("Outer:") {
            IntField($s.outerWidth)
            Text("px")
            ColorPicker("Outer colour", selection: $s.outerColour.pickerColor, supportsOpacity: true)
                .labelsHidden()
        }
        LabeledContent("Inner:") {
            IntField($s.innerWidth)
            Text("px")
            ColorPicker("Inner colour", selection: $s.innerColour.pickerColor, supportsOpacity: true)
                .labelsHidden()
        }
        LabeledContent("") {
            Text("An inner width of 0 draws one border.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TextStepView: View {
    @Binding var s: TextSettings
    @State private var fontTarget = FontPanelTarget()

    var body: some View {
        LabeledContent("Text:") {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $s.text)
                    .font(.body)
                    .frame(minWidth: 220, minHeight: 48, maxHeight: 72)
                    .border(.separator)
                PlaceholderButtons(placeholders: ["{name}", "{folder}", "{date}", "{n}"], text: $s.text)
            }
        }
        LabeledContent("Font:") {
            Button(fontLabel) {
                fontTarget.onChange = { s.fontName = $0 }
                fontTarget.show(fontName: s.fontName)
            }
            DoubleField($s.sizePercent)
            Text("% of the shorter side")
        }
        ColourRow("Colour:", $s.colour)
        LabeledContent("Position:") { AnchorPicker(anchor: $s.position) }
        DoubleRow("Margin:", $s.marginPercent, unit: "%")
        Picker("Place:", selection: $s.placement) {
            Text("In the Image").tag(TextPlacement.inImage)
            Text("On a Strip Below").tag(TextPlacement.stripBelow)
            Text("On a Strip Above").tag(TextPlacement.stripAbove)
        }
        .fixedSize()
        OpacityRow(opacity: $s.opacity)
        LabeledContent("") {
            VStack(alignment: .leading) {
                Toggle("Shadow", isOn: $s.shadow)
                HStack {
                    Toggle("Background box", isOn: $s.backgroundBox)
                    ColorPicker("Box colour", selection: $s.boxColour.pickerColor, supportsOpacity: true)
                        .labelsHidden()
                        .disabled(!s.backgroundBox)
                }
            }
        }
    }

    private var fontLabel: String {
        let name = NSFont(name: s.fontName, size: 12)?.displayName ?? s.fontName
        return String(localized: "\(name), \((s.sizePercent / 100).formatted(.percent))", comment: "Batch text: font name and size as a share of the picture")
    }
}

/// Receives the font panel's choice; only the face is used (the size is a share of the image).
@MainActor private final class FontPanelTarget: NSObject {
    var onChange: (String) -> Void = { _ in }

    func show(fontName: String) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(NSFont(name: fontName, size: 24) ?? .systemFont(ofSize: 24), isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let font = sender.convert(sender.selectedFont ?? .systemFont(ofSize: 24))
        // convert() changes only what was just touched, so the next change must start from this font.
        sender.setSelectedFont(font, isMultiple: false)
        onChange(font.fontName)
    }
}

private struct WatermarkStepView: View {
    @Binding var s: WatermarkSettings

    var body: some View {
        LabeledContent("Image:") {
            Text(s.path.isEmpty ? String(localized: "None") : (s.path as NSString).lastPathComponent)
                .foregroundStyle(s.path.isEmpty ? .secondary : .primary)
                .help(s.path)
            Button("Choose…", action: choose)
        }
        LabeledContent("Position:") { AnchorPicker(anchor: $s.position) }
        DoubleRow("Margin:", $s.marginPercent, unit: "%")
        DoubleRow("Width:", $s.widthPercent, unit: "% of the output's width")
        OpacityRow(opacity: $s.opacity)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        s.path = url.path
    }
}

private struct SafetyStep: View {
    @Binding var s: SafetySettings

    var body: some View {
        Toggle("Replace existing files (they move to the Trash)", isOn: $s.replaceExisting)
        Toggle("Move originals to the Trash after converting", isOn: $s.trashOriginals)
        Toggle("Keep file dates", isOn: $s.keepDates)
        Toggle("Recreate subfolders", isOn: $s.recreateSubfolders)
    }
}

// MARK: - Shared rows

/// Nine positions in the picture, each an accessible button. Picture positions don't mirror.
struct AnchorPicker: View {
    @Binding var anchor: ImageAnchor

    private static let rows: [[ImageAnchor]] = [
        [.topLeft, .top, .topRight], [.left, .center, .right], [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { cell in
                        Button { anchor = cell } label: {
                            Image(systemName: cell == anchor ? "square.fill" : "square")
                                .foregroundStyle(cell == anchor ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(Self.name(cell)))
                        .accessibilityAddTraits(cell == anchor ? .isSelected : [])
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Own keys: a picture position, worded apart from rotation's "Left"/"Right" in some languages.
    private static func name(_ anchor: ImageAnchor) -> LocalizedStringResource {
        switch anchor {
        case .topLeft: LocalizedStringResource("anchor.topLeft", defaultValue: "Top left", comment: "Picture position")
        case .top: LocalizedStringResource("anchor.top", defaultValue: "Top", comment: "Picture position")
        case .topRight: LocalizedStringResource("anchor.topRight", defaultValue: "Top right", comment: "Picture position")
        case .left: LocalizedStringResource("anchor.left", defaultValue: "Left", comment: "Picture position")
        case .center: LocalizedStringResource("anchor.center", defaultValue: "Centre", comment: "Picture position")
        case .right: LocalizedStringResource("anchor.right", defaultValue: "Right", comment: "Picture position")
        case .bottomLeft: LocalizedStringResource("anchor.bottomLeft", defaultValue: "Bottom left", comment: "Picture position")
        case .bottom: LocalizedStringResource("anchor.bottom", defaultValue: "Bottom", comment: "Picture position")
        case .bottomRight: LocalizedStringResource("anchor.bottomRight", defaultValue: "Bottom right", comment: "Picture position")
        }
    }
}

private struct IntField: View {
    @Binding var value: Int
    init(_ value: Binding<Int>) { _value = value }

    var body: some View {
        TextField("", value: $value, format: .number.grouping(.never))
            .labelsHidden()
            .frame(width: 64)
    }
}

private struct DoubleField: View {
    @Binding var value: Double
    init(_ value: Binding<Double>) { _value = value }

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .frame(width: 64)
    }
}

private struct IntRow: View {
    let label: LocalizedStringKey, unit: LocalizedStringKey, hint: LocalizedStringKey?
    @Binding var value: Int
    init(_ label: LocalizedStringKey, _ value: Binding<Int>, unit: LocalizedStringKey, hint: LocalizedStringKey? = nil) {
        self.label = label; _value = value; self.unit = unit; self.hint = hint
    }

    var body: some View {
        LabeledContent(label) {
            // The hint goes under the field: beside it, Canvas's long note made the card wider than its column.
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    IntField($value)
                    Text(unit)
                }
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct OptionalIntRow: View {
    let label: LocalizedStringKey, unit: LocalizedStringKey, prompt: LocalizedStringKey?
    @Binding var value: Int?
    init(_ label: LocalizedStringKey, _ value: Binding<Int?>, unit: LocalizedStringKey, prompt: LocalizedStringKey? = nil) {
        self.label = label; _value = value; self.unit = unit; self.prompt = prompt
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", value: $value, format: .number.grouping(.never), prompt: prompt.map { Text($0) })
                .labelsHidden()
                .frame(width: 64)
            Text(unit)
        }
    }
}

private struct DoubleRow: View {
    let label: LocalizedStringKey, unit: LocalizedStringKey
    @Binding var value: Double
    init(_ label: LocalizedStringKey, _ value: Binding<Double>, unit: LocalizedStringKey) {
        self.label = label; _value = value; self.unit = unit
    }

    var body: some View {
        LabeledContent(label) {
            DoubleField($value)
            Text(unit)
        }
    }
}

/// A slider with its number field; the range is the setting's valid range.
private struct SliderRow: View {
    let label: LocalizedStringKey, range: ClosedRange<Int>
    @Binding var value: Int
    init(_ label: LocalizedStringKey, _ value: Binding<Int>, _ range: ClosedRange<Int>) {
        self.label = label; _value = value; self.range = range
    }

    var body: some View {
        LabeledContent(label) {
            Slider(value: Binding { Double(value) } set: { value = Int($0.rounded()) },
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .frame(minWidth: 160)
            TextField("", value: $value, format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 56)
        }
    }
}

private struct OpacityRow: View {
    @Binding var opacity: Double

    var body: some View {
        LabeledContent("Opacity:") {
            Slider(value: $opacity, in: 0...1)
                .frame(minWidth: 160)
            Text(opacity.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}

private struct ColourRow: View {
    let label: LocalizedStringKey
    @Binding var colour: RGBAColor
    init(_ label: LocalizedStringKey, _ colour: Binding<RGBAColor>) { self.label = label; _colour = colour }

    var body: some View {
        LabeledContent(label) {
            ColorPicker(label, selection: $colour.pickerColor, supportsOpacity: true)
                .labelsHidden()
        }
    }
}

extension RGBAColor {
    /// For `ColorPicker`: read and written as sRGB.
    var pickerColor: CGColor {
        get { cgColor }
        set {
            guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let c = newValue.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
                  c.count >= 4 else { return }
            self = RGBAColor(red: c[0], green: c[1], blue: c[2], alpha: c[3])
        }
    }
}
