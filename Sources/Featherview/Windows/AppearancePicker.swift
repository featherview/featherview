import FeatherviewCore
import SwiftUI

/// Preferences › Viewer › Appearance: three miniature Featherview windows, light, dark and System split
/// corner to corner. A click sets the whole app's appearance.
struct AppearancePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: Theme.previewGap) {
            tile(.system, "System")
            tile(.light, "Light")
            tile(.dark, "Dark")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.previewGap / 2)
    }

    private func tile(_ mode: AppearanceMode, _ name: LocalizedStringKey) -> some View {
        let selected = AppearanceMode(stored: selection) == mode
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.preview)
        return Button {
            selection = mode.rawValue
        } label: {
            VStack(spacing: 8) {
                preview(mode)
                    .frame(width: Theme.previewSize.width, height: Theme.previewSize.height)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Theme.separator) }
                    .padding(Theme.previewRing + 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.preview + Theme.previewRing + 1)
                            .strokeBorder(selected ? Theme.accent : .clear, lineWidth: Theme.previewRing)
                    }
                Text(name)
                    .font(selected ? Theme.previewLabelSelected : Theme.previewLabel)
                    .foregroundStyle(selected ? Theme.accent : Theme.labelPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func preview(_ mode: AppearanceMode) -> some View {
        switch mode {
        case .light: MiniWindow().environment(\.colorScheme, .light)
        case .dark: MiniWindow().environment(\.colorScheme, .dark)
        case .system:
            ZStack {
                MiniWindow(picture: false).environment(\.colorScheme, .light)
                MiniWindow(picture: false).environment(\.colorScheme, .dark).clipShape(LowerTrailingHalf())
                MiniWindow(chrome: false)  // one picture over both halves: no seam across it
            }
        }
    }
}

/// The viewer at a glance: toolbar capsules, a fitted picture, the status strip, on the background.
private struct MiniWindow: View {
    var chrome = true
    var picture = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                if chrome {
                Color(nsColor: Theme.background)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.labelTertiary).frame(width: 4, height: 4) }
                    Spacer()
                    Capsule().fill(Theme.glassFill).frame(width: w * 0.3, height: 7)
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                Capsule().fill(Theme.glassFill)
                    .frame(width: w - 12, height: 6)
                    .position(x: w / 2, y: h - 7)
                }
                if picture {
                    MiniPicture()
                        .frame(width: w * 0.5, height: h * 0.5)
                        .elevation(.e1)
                        .position(x: w / 2, y: h * 0.5)
                }
            }
        }
    }
}

/// Sky and two hills, so the tile reads as a picture in any appearance.
private struct MiniPicture: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var back = Path()
            back.move(to: CGPoint(x: 0, y: h * 0.75))
            back.addQuadCurve(to: CGPoint(x: w, y: h * 0.6), control: CGPoint(x: w * 0.45, y: h * 0.25))
            back.addLine(to: CGPoint(x: w, y: h)); back.addLine(to: CGPoint(x: 0, y: h))
            context.fill(back, with: .color(Theme.previewHillBack))
            var front = Path()
            front.move(to: CGPoint(x: 0, y: h * 0.9))
            front.addQuadCurve(to: CGPoint(x: w, y: h * 0.85), control: CGPoint(x: w * 0.7, y: h * 0.45))
            front.addLine(to: CGPoint(x: w, y: h)); front.addLine(to: CGPoint(x: 0, y: h))
            context.fill(front, with: .color(Theme.previewHillFront))
        }
        .background(Theme.previewSky)
    }
}

/// The half below the line from the top-trailing to the bottom-leading corner.
private struct LowerTrailingHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
