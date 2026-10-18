import AppKit
import SwiftUI

/// The one glass recipe (docs/DESIGN.md "Materials"), in the shape of each surface: Liquid Glass on
/// macOS 26, the system material with the design's hairline and highlight on 14/15. Both take the
/// surface's elevation and, for panels and sheets, the denser fill token on top.
enum GlassSurface {
    /// Toolbar groups and the status strip: E2, no extra fill.
    case chrome
    /// The empty hint card and message boxes: E3, no extra fill.
    case card
    /// The info panel: E3, panel fill at 25 %.
    case panel
    /// Folder chooser, Move/Copy to Folder: E4, sheet fill at 35 %.
    case sheet

    var elevation: Theme.Elevation {
        switch self {
        case .chrome: .e2
        case .card, .panel: .e3
        case .sheet: .e4
        }
    }

    var fill: Color? {
        switch self {
        case .chrome, .card: nil
        case .panel: Theme.panelFill.opacity(Theme.panelFillOpacity)
        case .sheet: Theme.sheetFill.opacity(Theme.sheetFillOpacity)
        }
    }
}

extension View {
    /// This view on glass in `shape`.
    func glass(_ surface: GlassSurface, in shape: some Shape) -> some View {
        modifier(GlassBackground(surface: surface, shape: shape))
    }

    /// On glass in a rounded rectangle.
    func glass(_ surface: GlassSurface, cornerRadius: CGFloat) -> some View {
        glass(surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct GlassBackground<S: Shape>: ViewModifier {
    let surface: GlassSurface
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background { if let fill = surface.fill { shape.fill(fill) } }
                .glassEffect(.regular, in: shape)
                .background { ShadowOnly(shape: shape, level: surface.elevation) }
        } else {
            content
                .background {
                    ZStack {
                        SystemMaterial().clipShape(shape)
                        if let fill = surface.fill { shape.fill(fill) }
                        // 1 pt light along the top edge, following the curve, then the outline.
                        shape.subtracting(shape.offset(y: 1)).fill(Theme.glassHighlight)
                        shape.stroke(Theme.glassHairline, lineWidth: 1)
                    }
                    .clipShape(shape)
                    .background { ShadowOnly(shape: shape, level: surface.elevation) }
                }
        }
    }
}

/// The macOS 14/15 material: `.hudWindow` in the dark appearance, `.popover` in the light one.
private struct SystemMaterial: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState  // as Liquid Glass and the toolbar do
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = colorScheme == .dark ? .hudWindow : .popover
    }
}

/// A shape's shadow without the shape: glass is translucent, so a filled shape under it would show,
/// and a shadow on the content would also shade its text.
private struct ShadowOnly<S: Shape>: View {
    let shape: S
    let level: Theme.Elevation

    var body: some View {
        shape.fill(.black)
            .elevation(level)
            .mask { Outside(shape: shape).fill(style: FillStyle(eoFill: true)) }
    }

    /// Everything around the shape, far enough out for the widest shadow.
    private struct Outside: Shape {
        let shape: S

        func path(in rect: CGRect) -> Path {
            var path = Path(rect.insetBy(dx: -100, dy: -100))
            path.addPath(shape.path(in: rect))
            return path
        }
    }
}

