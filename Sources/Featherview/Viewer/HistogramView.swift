import FeatherviewCore
import SwiftUI

/// The info panel's histogram block: its label, the Luminance / RGB control, and the 60 pt plot with a clip mark
/// in each bottom corner (spec "Info panel"). Shadows stay on the left in right-to-left languages.
struct HistogramView: View {
    let histogram: Histogram?
    var focus: FocusState<InfoFocus?>.Binding
    /// Secondary text and hairlines under Increase Contrast.
    let secondary: Color
    let hairline: CGFloat
    private let state = InfoPanelState.shared
    /// The clip mark whose share shows in a bubble.
    @State private var bubble: InfoFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The curves' height, 0 at the baseline: below 1 once a histogram went away with the panel open, so the next
    /// one rises. One that arrives while the panel slides in shows at once.
    @State private var rise: CGFloat = 1
    @State private var shownSince = Date.distantFuture

    var body: some View {
        VStack(spacing: Theme.infoSmallGap) {
            HStack {
                Text("Histogram", comment: "Info panel section").font(Theme.infoSection).foregroundStyle(secondary)
                Spacer(minLength: 0)
                modeControl
            }
            .padding(.horizontal, Theme.infoHeaderPadding)
            plot
            if let headroom = histogram?.headroom { scale(headroom) }
        }
    }

    private var modeName: String {
        state.mode == .luminance ? String(localized: "Luminance histogram", comment: "Info panel, VoiceOver")
            : String(localized: "RGB histogram", comment: "Info panel, VoiceOver")
    }

    private var modeControl: some View {
        HStack(spacing: 2) {
            segment(.luminance, Text("Luminance", comment: "Info panel histogram mode"))
            segment(.rgb, Text(verbatim: "RGB"))
        }
        .padding(2)
        .background(Theme.cardFill, in: .rect(cornerRadius: Theme.Radius.histogram))
        .infoControl(.mode, focus: focus, radius: Theme.Radius.histogram) { switchMode() }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            switchMode()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Histogram mode", comment: "Info panel, VoiceOver"))
        .accessibilityValue(state.mode == .luminance ? Text("Luminance", comment: "Info panel histogram mode") : Text(verbatim: "RGB"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { _ in switchMode() }
    }

    private func segment(_ mode: HistogramMode, _ label: Text) -> some View {
        let on = state.mode == mode
        // A button, not a tap gesture: the panel's selectable text would take the click first.
        return Button { state.mode = mode } label: {
            label
                .font(Theme.infoSegment)
                .foregroundStyle(on ? Theme.accent : secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(on ? Theme.toggledPill : .clear, in: .rect(cornerRadius: Theme.Radius.keyCap))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func switchMode() { state.mode = state.mode == .luminance ? .rgb : .luminance }

    private var plot: some View {
        Canvas { context, size in
            Self.drawGrid(&context, size: size, headroom: histogram?.headroom, hairline: hairline)
        }
        .overlay { curves.scaleEffect(x: 1, y: rise, anchor: .bottom) }
        .onAppear { shownSince = .now }
        .onChange(of: histogram == nil) { _, missing in
            if missing {
                if !reduceMotion, Date.now.timeIntervalSince(shownSince) > Theme.Motion.panel { rise = 0 }
            } else if rise < 1 {
                withAnimation(.easeOut(duration: Theme.Motion.histogramRise)) { rise = 1 }
            }
        }
        .frame(height: Theme.histogramHeight)
        .background(Theme.cardFill, in: .rect(cornerRadius: Theme.Radius.histogram))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.histogram).strokeBorder(Theme.cardLine, lineWidth: hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(modeName)
        .accessibilityValue(clippingSummary)
        .overlay(alignment: .bottomLeading) { clipMark(.shadowsClip) }
        .overlay(alignment: .bottomTrailing) { clipMark(.highlightsClip) }
        .overlay(alignment: .top) { bubbleText }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var curves: some View {
        Canvas { context, size in
            guard let histogram else { return }
            if state.mode == .rgb {
                for (bins, colour) in [(histogram.red, Theme.histogramChannelRed), (histogram.green, Theme.histogramChannelGreen),
                                       (histogram.blue, Theme.histogramChannelBlue)] {
                    context.stroke(Self.line(bins, size), with: .color(colour), lineWidth: 1)
                }
            }
            var fill = Self.line(histogram.luminance, size)
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(Theme.histogramFill))
            context.stroke(Self.line(histogram.luminance, size), with: .color(Theme.histogramLine), lineWidth: 1.5)
        }
    }

    private var clippingSummary: String {
        guard let histogram else { return "" }
        let parts = [(histogram.shadowsClipped, false), (histogram.highlightsClipped, true)]
            .filter { $0.0 > histogram.clipThreshold }
            .map { HistogramText.clipped($0.0, highlights: $0.1) }
        return parts.isEmpty ? String(localized: "Nothing clipped", comment: "Info panel histogram, VoiceOver") : parts.joined(separator: ", ")
    }

    private func fraction(_ mark: InfoFocus) -> Double? {
        mark == .shadowsClip ? histogram?.shadowsClipped : histogram?.highlightsClipped
    }

    private func clipMark(_ mark: InfoFocus) -> some View {
        let clipped = histogram.map { fraction(mark)! > $0.clipThreshold } ?? false
        let shape = ClipTriangle()
        return Button { bubble = bubble == mark ? nil : mark } label: {
            ZStack {
                if clipped { shape.fill(Theme.accent) }
                shape.stroke(clipped ? Theme.accent : Theme.clipMarkOff, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
            .frame(width: 11, height: 10)
            .padding(3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Never disabled while the next picture is counted: a disabled mark drops the focus to nothing.
        .infoControl(mark, focus: focus, radius: Theme.Radius.small) { bubble = bubble == mark ? nil : mark }
        .accessibilityLabel(mark == .shadowsClip ? Text("Shadows clipping", comment: "Info panel histogram clip mark, VoiceOver")
                            : Text("Highlights clipping", comment: "Info panel histogram clip mark, VoiceOver"))
        .accessibilityValue(fraction(mark).map { HistogramText.clipped($0, highlights: mark == .highlightsClip) } ?? "")
    }

    @ViewBuilder private var bubbleText: some View {
        if let bubble, let value = fraction(bubble) {
            Text(verbatim: HistogramText.clipped(value, highlights: bubble == .highlightsClip))
                .font(Theme.infoCaption)
                .foregroundStyle(Theme.labelPrimary)
                .padding(Theme.footerKeyCapPadding)
                .background(Color(nsColor: Theme.background), in: .rect(cornerRadius: Theme.Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.chipLine, lineWidth: hairline))
                .frame(maxWidth: .infinity, alignment: bubble == .highlightsClip ? .trailing : .leading)
                .padding(Theme.infoSmallGap)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// "0", the dashed 1.0 marker's label, and the headroom ("3.2×") under an HDR plot.
    private func scale(_ headroom: Double) -> some View {
        GeometryReader { geo in
            Text(verbatim: 1.0.formatted(.number.precision(.fractionLength(1))))
                .position(x: geo.size.width / headroom, y: geo.size.height / 2)
            Text(verbatim: "\(headroom.formatted(.number.precision(.fractionLength(0...1))))×")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .font(Theme.infoTileUnit.monospacedDigit())
        .foregroundStyle(secondary)
        .frame(height: 13)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }

    /// The bins' top edge, bin 0 at the leading edge, the tallest luminance bin at the top.
    private static func line(_ bins: [Float], _ size: CGSize) -> Path {
        Path { path in
            for (i, value) in bins.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, bins.count - 1)),
                                    y: size.height * (1 - CGFloat(min(1, max(0, value)))))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }

    /// Quarter lines; for HDR the dashed 1.0 marker (SDR white) at 1 / headroom of the width.
    private static func drawGrid(_ context: inout GraphicsContext, size: CGSize, headroom: Double?, hairline: CGFloat) {
        var grid = Path()
        for quarter in 1...3 {
            let x = (size.width * CGFloat(quarter) / 4).rounded() + 0.5
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(grid, with: .color(Theme.rowSeparator), lineWidth: hairline)
        guard let headroom, headroom > 1 else { return }
        let x = size.width / headroom
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: 0))
        marker.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(marker, with: .color(Theme.labelSecondary), style: StrokeStyle(lineWidth: hairline, dash: [3, 2]))
    }
}

/// A clip mark: a small triangle pointing up.
private struct ClipTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
