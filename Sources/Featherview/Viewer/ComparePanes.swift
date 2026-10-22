import FeatherviewCore
import SwiftUI

/// Compare mode: two panes of equal width with a 1 pt divider, each with its own strip. An `HStack`, so pane 1 is at
/// the leading side (on the right in right-to-left languages); each picture itself never mirrors.
struct ComparePanes<First: View>: View {
    let model: ViewerModel
    let session: CompareSession
    /// Pane 1: the viewer's own canvas, built by the view.
    let first: First
    /// One pane's insets and fit area.
    let insets: CanvasInsets
    let fitArea: CGSize
    let displayScale: Double
    let checkerboard: Bool
    let showsStrips: Bool
    let stripsVisible: Bool
    let secondPan: PanController
    /// Pane 1's draw size and pixel width for a picture of its decoded size; the difference is drawn with them.
    let firstLayout: (CGImage) -> (size: CGSize, pixelWidth: Double)
    let onSwipe: (_ likeRightArrow: Bool) -> Void
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            pane(.first) { first }
            Theme.separator.frame(width: Theme.compareDivider)
            pane(.second) { second }
        }
        .ignoresSafeArea()
        // Pane 1's picture, size or zoom changed: pane 2 decodes again only when it needs another decode.
        .onChange(of: model.secondZoom, initial: true) { model.showSecond() }
        .onChange(of: session.url) { model.showSecond() }
    }

    private func pane(_ which: CompareSession.Pane, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if showsStrips {
                    StatusBar(model: model, pane: which)
                        .opacity(stripsVisible ? 1 : 0)
                        .animation(Theme.Motion.fade(stripsVisible ? Theme.Motion.barsIn : Theme.Motion.barsOut),
                                   value: stripsVisible)
                }
            }
    }

    @ViewBuilder private var second: some View {
        if let image = session.image {
            // One canvas for both, so turning the difference on or off keeps the scroll position.
            let shown = differenceShown
            ImageCanvas(image: shown?.image ?? image, size: shown?.size ?? drawSize(image),
                        pixelWidth: shown?.pixelWidth ?? pixelSize(image).width, displayScale: displayScale,
                        background: Theme.background, insets: insets, zoom: shown == nil ? model.secondZoom : model.shownZoom,
                        checkerboard: checkerboard, transform: shown == nil ? PictureTransform() : model.pendingTransform,
                        panController: secondPan, onDoubleClick: model.toggleFullScreen, onPinch: model.zoom(by:),
                        onSwipe: onSwipe, onClick: onClick, onCommit: model.secondCommitted, animatesZoom: false,
                        compareLink: model.compareLink, pane: .second)
                .contextMenu {
                    Button("Swap Images") { model.swapCompared() }
                        .disabled(!model.availability.canSwap)
                    Button("Stop Comparing") { model.leaveCompare() }
                    Divider()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.url]) }
                }
        } else if let message = session.errorMessage {
            Text(message)
                .messageBox()
                .padding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing))
        } else {
            Color(nsColor: Theme.background)
        }
    }

    /// The difference, drawn exactly as pane 1 draws its picture, once it has landed.
    private var differenceShown: (image: CGImage, size: CGSize, pixelWidth: Double)? {
        guard session.showsDifference, let difference = session.difference, let first = model.image else { return nil }
        let layout = firstLayout(first)
        return (difference, layout.size, layout.pixelWidth)
    }

    /// At pane 2's zoom from the file's full pixel size, so a smaller decode already has its final size.
    private func drawSize(_ image: CGImage) -> CGSize {
        let factor: Double? = if case .factor(let factor) = model.secondZoom { factor } else { nil }
        return ZoomSteps.drawSize(decoded: CGSize(width: image.width, height: image.height), full: session.info?.pixelSize,
                                  factor: factor, view: fitArea, displayScale: displayScale)
    }

    private func pixelSize(_ image: CGImage) -> CGSize {
        ZoomSteps.pixelSize(decoded: CGSize(width: image.width, height: image.height), full: session.info?.pixelSize)
    }
}
