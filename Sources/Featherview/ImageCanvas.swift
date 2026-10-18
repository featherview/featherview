import AppKit
import FeatherviewCore
import SwiftUI

/// Lets the viewer pan the canvas with the arrow keys; the canvas registers its scroll view here.
@MainActor
final class PanController {
    fileprivate weak var scrollView: NSScrollView?

    /// Pans one step if the image is larger than the view along that axis; false if it isn't
    /// (the arrow then changes images). `dx`/`dy` are -1, 0 or 1; physical directions, never mirrored.
    func pan(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let visible = scrollView.clearRect
        let canPan = dx != 0 ? document.frame.width > visible.width + 0.5 : document.frame.height > visible.height + 0.5
        guard canPan else { return false }
        let step: CGFloat = 80
        moveVisibleOrigin(scrollView, to: CGPoint(x: visible.origin.x + dx * step, y: visible.origin.y + dy * step))
        return true
    }
}

/// Moves the clear area (between the bars) so its top-leading corner is at `point` in the document.
@MainActor
private func moveVisibleOrigin(_ scrollView: NSScrollView, to point: CGPoint) {
    let clip = scrollView.contentView
    let origin = CGPoint(x: point.x - clip.contentInsets.left, y: point.y - clip.contentInsets.top)
    let target = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
    cut { clip.animator().setBoundsOrigin(target) }
    scrollView.reflectScrolledClipView(clip)
}

/// Applies the changes at once and replaces a zoom animation still running on them:
/// a plain setter doesn't stop an animator animation, which would step on to its old target.
@MainActor private func cut(_ changes: () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        changes()
    }
}

private extension NSScrollView {
    /// The part of the view not under the toolbar or the status strip, in document coordinates
    /// (the document view is flipped, so the top inset is at the low y).
    @MainActor var clearRect: NSRect {
        let bounds = contentView.bounds, insets = contentInsets
        return NSRect(x: bounds.minX + insets.left, y: bounds.minY + insets.top,
                      width: bounds.width - insets.left - insets.right,
                      height: bounds.height - insets.top - insets.bottom)
    }
}

/// The image in an AppKit scroll view: two-finger scroll and dragging pan a zoomed image, a pinch zooms
/// about the pointer, a sideways swipe with nothing to pan changes images, a small image sits centred,
/// double-click toggles full screen. SwiftUI's ScrollView can't pan by dragging.
struct ImageCanvas: NSViewRepresentable {
    let image: CGImage
    /// Size in points the image is drawn at.
    let size: CGSize
    /// The file's pixel width the image stands for (wider than `image` while a smaller decode shows).
    let pixelWidth: Double
    let displayScale: Double
    let background: NSColor
    /// How far the toolbar and the status strip reach over the canvas: fit stays clear of them,
    /// a zoomed image scrolls under them.
    let insets: CanvasInsets
    /// A change of it on the same image animates the resize (spec "Look"); a new image never animates.
    let zoom: ViewerModel.Zoom
    let checkerboard: Bool
    /// Quarter turns to show the picture turned by, animated about its centre (R / L before the file is rewritten).
    var turns = 0
    /// Fades the picture out (Trash or a move); a new image shows at full opacity.
    var leaving = false
    let panController: PanController
    let onDoubleClick: () -> Void
    /// A pinch step: the zoom multiplier (above 1 zooms in).
    var onPinch: (Double) -> Void = { _ in }
    /// A completed swipe: true when it goes the way → does (fingers moving left).
    var onSwipe: (_ likeRightArrow: Bool) -> Void = { _ in }
    /// Any click on the image, and each step of a drag: the viewer takes the keyboard back (e.g. from the
    /// Info panel's text) and counts it as activity for the auto-hiding bars, which get no hover while a button is down.
    var onClick: () -> Void = {}
    /// Called once the first image this canvas shows is committed to the screen.
    var onFirstDraw: @MainActor () -> Void = {}
    /// Called with each new image once Core Animation has committed it (the `Navigate` signpost ends here).
    var onCommit: @MainActor (CGImage) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CanvasScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.automaticallyAdjustsContentInsets = false
        // The picture never mirrors (spec "Languages"): scroll origin and dragging stay physical.
        scrollView.userInterfaceLayoutDirection = .leftToRight
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = ImageLayerView()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        panController.scrollView = scrollView
        scrollView.backgroundColor = background
        guard let view = scrollView.documentView as? ImageLayerView else { return }
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
        view.onFirstDraw = onFirstDraw
        view.onCommit = onCommit
        let canvas = scrollView as? CanvasScrollView
        canvas?.onPinch = onPinch
        canvas?.onSwipe = onSwipe
        // A pinch zooms about the pointer at once; a step or Fit about the centre of the clear area, animated.
        let pinch = canvas?.takePinch()
        let oldSize = view.frame.size
        let oldFrameOrigin = view.frame.origin
        let oldVisible = scrollView.clearRect
        // Keep the point under the pointer (pinch) or at the centre of the clear area where it was,
        // so zooming doesn't jump to a corner.
        let anchor = pinch.map { view.convert($0, from: nil) } ?? CGPoint(x: oldVisible.midX, y: oldVisible.midY)
        let centre = CGPoint(x: oldSize.width > 0 ? anchor.x / oldSize.width : 0.5,
                             y: oldSize.height > 0 ? anchor.y / oldSize.height : 0.5)
        // The scroll view stays left-to-right (the picture never mirrors); the panel side follows the layout.
        let rtl = context.environment.layoutDirection == .rightToLeft
        let contentInsets = NSEdgeInsets(top: insets.top, left: rtl ? insets.trailing : insets.leading,
                                         bottom: insets.bottom, right: rtl ? insets.leading : insets.trailing)
        let oldInsets = scrollView.contentInsets
        // Before the new insets re-centre the clip: an animation starts from where the picture is on screen.
        let oldOrigin = scrollView.contentView.bounds.origin
        let insetsChanged = !NSEdgeInsetsEqual(oldInsets, contentInsets)
        // Only a side changed: the info panel opened or closed, and the picture refits on its curve.
        let panelMoved = insetsChanged && oldInsets.top == contentInsets.top && oldInsets.bottom == contentInsets.bottom
        if insetsChanged {
            scrollView.contentInsets = contentInsets
            scrollView.scrollerInsets = contentInsets
        }
        let zoomChanged = view.zoom != nil && view.zoom != zoom && !insetsChanged
        let panelRefit = panelMoved && view.zoom == zoom
        let animate = view.shows(image) && (zoomChanged || panelRefit) && pinch == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.zoom = zoom
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sameImage = view.shows(image)
        view.show(image, checkerboard: checkerboard && image.hasAlpha, 
                  smooth: !ZoomSteps.showsPixels(drawnWidth: size.width, imageWidth: Int(pixelWidth), displayScale: displayScale))
        // A fit picture turned a quarter ends at the size it will fit at, not overflowing.
        let clearSize = CGSize(width: scrollView.contentView.bounds.width - contentInsets.left - contentInsets.right,
                               height: scrollView.contentView.bounds.height - contentInsets.top - contentInsets.bottom)
        let turnScale = zoom == .fit && turns % 2 != 0 && size.width > 0 && size.height > 0
            ? min(1, clearSize.width / size.height, clearSize.height / size.width) : 1
        view.turn(to: turns, scale: turnScale, animated: sameImage && !reduceMotion)
        if leaving, sameImage { view.fadeOut() }
        // The size last asked for, not the frame: mid-animation the frame is part-way, and a new image
        // at the same zoom must leave the running animation alone.
        let resized = view.targetSize != size
        view.targetSize = size
        // E3 shadow and hairline only while the picture fits the clear area (a transparent one would show it through).
        let clear = scrollView.contentView.bounds.size
        let fits = size.width <= clear.width - contentInsets.left - contentInsets.right + 0.5
            && size.height <= clear.height - contentInsets.top - contentInsets.bottom + 0.5
        let framed = fits && (!image.hasAlpha || checkerboard)
        // Off at the first frame beyond fit; on once a zoom back into fit has landed.
        if !framed || !(animate && (resized || insetsChanged)) { view.setFramed(framed) }
        if resized || insetsChanged {
            let clip = scrollView.contentView
            cut { view.animator().setFrameSize(size) }
            let visible = scrollView.clearRect
            let offset = pinch == nil ? CGPoint(x: visible.width / 2, y: visible.height / 2)
                : CGPoint(x: anchor.x - oldVisible.minX, y: anchor.y - oldVisible.minY)
            let point = CGPoint(x: centre.x * size.width - offset.x, y: centre.y * size.height - offset.y)
            guard animate else { return moveVisibleOrigin(scrollView, to: point) }
            if panelRefit {
                // The clip keeps a picture smaller than the clear area centred, which overrides an animated scroll
                // position: the picture's layer moves from its old place on screen to its new one instead.
                let old = CGRect(x: oldFrameOrigin.x - oldOrigin.x, y: oldFrameOrigin.y - oldOrigin.y,
                                 width: oldSize.width, height: oldSize.height)
                moveVisibleOrigin(scrollView, to: point)
                let new = CGRect(x: view.frame.minX - clip.bounds.minX, y: view.frame.minY - clip.bounds.minY,
                                 width: size.width, height: size.height)
                view.slide(from: old, to: new)
                return view.setFramed(framed)
            }
            // The target scroll position is worked out at the final size, then both animate from the old one.
            let target = clip.constrainBoundsRect(NSRect(
                origin: CGPoint(x: point.x - clip.contentInsets.left, y: point.y - clip.contentInsets.top),
                size: clip.bounds.size)).origin
            // Shrinking the document clamped (or centred) the clip's origin: put back where the user was looking.
            cut {
                view.animator().setFrameSize(oldSize)
                clip.animator().setBoundsOrigin(oldOrigin)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = panelRefit ? Theme.Motion.panel : Theme.Motion.zoom
                context.timingFunction = CAMediaTimingFunction(name: panelRefit ? .easeInEaseOut : .easeOut)
                view.animator().setFrameSize(size)
                clip.animator().setBoundsOrigin(target)
            } completionHandler: {
                MainActor.assumeIsolated {
                    scrollView.reflectScrolledClipView(clip)
                    if framed, view.targetSize == size { view.setFramed(true) }
                }
            }
        }
    }
}

private extension CGImage {
    var hasAlpha: Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }
}

/// A trackpad or wheel scroll stops a running zoom animation, which would otherwise snap the
/// clip back to its target once it ends and undo the scroll. Pinches and swipes go to the viewer.
private final class CanvasScrollView: NSScrollView {
    var onPinch: (Double) -> Void = { _ in }
    var onSwipe: (_ likeRightArrow: Bool) -> Void = { _ in }
    /// The pointer at the last pinch step (window coordinates) and when, until the canvas zooms about it.
    private var pinch: (location: CGPoint, time: TimeInterval)?

    /// The pointer of a pinch step just taken; nil otherwise, also for one clamped at the zoom limit
    /// that changed nothing, so a later key zoom isn't taken for a pinch.
    func takePinch() -> CGPoint? {
        defer { pinch = nil }
        guard let pinch, ProcessInfo.processInfo.systemUptime - pinch.time < 0.25 else { return nil }
        return pinch.location
    }

    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        pinch = (event.locationInWindow, event.timestamp)
        onPinch(1 + event.magnification)
    }

    /// Three-finger swipes, when the trackpad is set to swipe between pages with three fingers.
    override func swipe(with event: NSEvent) {
        if event.deltaX != 0 { onSwipe(event.deltaX < 0) }
    }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger swipe between pages (the system setting), only when there's nothing to pan sideways.
        if event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
           abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
           let document = documentView, document.frame.width <= clearRect.width + 0.5 {
            event.trackSwipeEvent(options: .lockDirection, dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, phase, complete, _ in
                if phase == .ended, complete { self?.onSwipe(amount < 0) }
            }
            return
        }
        let clip = contentView
        cut { clip.animator().setBoundsOrigin(clip.bounds.origin) }
        super.scrollWheel(with: event)
    }
}

/// Keeps a document smaller than the clear area (inside the content insets) in its middle
/// instead of the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let insets = contentInsets
        let clearWidth = rect.width - insets.left - insets.right
        let clearHeight = rect.height - insets.top - insets.bottom
        if document.frame.width < clearWidth {
            rect.origin.x = -insets.left - (clearWidth - document.frame.width) / 2
        }
        // The document view is flipped: the top inset is at the low y.
        if document.frame.height < clearHeight {
            rect.origin.y = -insets.top - (clearHeight - document.frame.height) / 2
        }
        return rect
    }
}

/// Draws the image with Core Animation and pans its scroll view while dragged.
private final class ImageLayerView: NSView {
    var onDoubleClick: () -> Void = {}
    var onClick: () -> Void = {}
    var onFirstDraw: @MainActor () -> Void = {}
    var onCommit: @MainActor (CGImage) -> Void = { _ in }
    /// The zoom the frame was last sized for; nil before the first update.
    var zoom: ViewerModel.Zoom?
    /// The frame size the canvas last asked for (the animation's end while one runs); nil before the first update.
    var targetSize: CGSize?
    private let imageLayer = CALayer()
    /// The E3 elevation's contact and ambient shadows and the picture hairline, while the picture fits.
    private let shadowLayers = Theme.Elevation.e3.layers.map { _ in CALayer() }
    private let hairline = CALayer()
    private var framed = false
    private var shownTurns = 0
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        for shadow in shadowLayers.reversed() { layer?.addSublayer(shadow) }
        hairline.borderWidth = 1
        layer?.addSublayer(hairline)
        layer?.addSublayer(imageLayer)
        setFramed(false)
    }

    func setFramed(_ on: Bool) {
        framed = on
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for (layer, spec) in zip(shadowLayers, Theme.Elevation.e3.layers) {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = on ? Float(dark ? spec.dark : spec.light) : 0
            layer.shadowRadius = spec.radius
            layer.shadowOffset = CGSize(width: 0, height: spec.y)  // the layer is flipped: positive is down
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { hairline.borderColor = Theme.pictureHairline.cgColor }
        hairline.isHidden = !on
        layoutFrameLayers()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        setFramed(framed)
    }

    private func layoutFrameLayers() {
        for layer in shadowLayers {
            place(layer)
            layer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        }
        place(hairline, outset: 1)
    }

    /// Bounds and position, not frame: the layers may carry a rotation (`turn`).
    private func place(_ layer: CALayer, outset: CGFloat = 0) {
        layer.bounds = CGRect(x: 0, y: 0, width: bounds.width + 2 * outset, height: bounds.height + 2 * outset)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Turns the picture, its shadow and hairline about the centre; a new image takes `turns` without animation.
    func turn(to turns: Int, scale: CGFloat, animated: Bool) {
        guard turns != shownTurns else { return }
        shownTurns = turns
        // The view is flipped, so a positive angle turns clockwise on screen.
        let transform = CATransform3DScale(CATransform3DMakeRotation(CGFloat(turns) * .pi / 2, 0, 0, 1), scale, scale, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(Theme.Motion.rotation)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        for layer in [imageLayer, hairline] + shadowLayers { layer.transform = transform }
        CATransaction.commit()
    }

    /// Moves the picture on screen from `old` to `new` (where it is now) with the info panel's curve.
    func slide(from old: CGRect, to new: CGRect) {
        guard let layer, new.width > 0 else { return }
        let scale = old.width / new.width
        // The layer's anchor is its top-leading corner (flipped), at `new.origin`: scale about it, then move.
        let from = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                       CATransform3DMakeTranslation(old.minX - new.minX, old.minY - new.minY, 0))
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = from
        animation.toValue = CATransform3DIdentity
        animation.duration = Theme.Motion.panel
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "refit")
    }

    /// The picture fades out (opacity only, kept under Reduce Motion).
    func fadeOut() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Motion.leave)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        imageLayer.opacity = 0
        CATransaction.commit()
    }

    func shows(_ image: CGImage) -> Bool { (imageLayer.contents as AnyObject?) === image }

    func show(_ image: CGImage, checkerboard: Bool, smooth: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // no fade between images
        if imageLayer.contents == nil { ViewerModel.afterFrame(onFirstDraw) }
        if (imageLayer.contents as AnyObject?) !== image {
            imageLayer.contents = image
            imageLayer.opacity = 1
            let onCommit = onCommit
            CATransaction.setCompletionBlock { MainActor.assumeIsolated { onCommit(image) } }
        }
        // Same transaction as `contents`, so an SDR image after an HDR one never flashes bright.
        let isHDR = image.bitsPerComponent > 8  // display decodes are 8-bit unless HDR
        if #available(macOS 26, *) {
            imageLayer.preferredDynamicRange = isHDR ? .high : .standard
        } else {
            imageLayer.wantsExtendedDynamicRangeContent = isHDR
        }
        place(imageLayer)
        // Below 2× smooth; from 2× on, show the pixels.
        imageLayer.magnificationFilter = smooth ? .linear : .nearest
        imageLayer.minificationFilter = .trilinear
        layer?.backgroundColor = checkerboard ? Self.checkerColor : nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(imageLayer)
        if framed { layoutFrameLayers() }
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
        if event.clickCount == 2 { return onDoubleClick() }
        guard let scrollView = enclosingScrollView else { return }
        dragStart = (event.locationInWindow, scrollView.clearRect.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        onClick()
        guard let dragStart, let scrollView = enclosingScrollView else { return }
        // The image follows the pointer: moving the pointer right shows more of the left side.
        let dx = event.locationInWindow.x - dragStart.mouse.x
        let dy = event.locationInWindow.y - dragStart.mouse.y
        moveVisibleOrigin(scrollView, to: CGPoint(x: dragStart.origin.x - dx, y: dragStart.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    /// Grey and white 8-point squares behind transparent images.
    private static let checkerColor: CGColor = {
        let tile = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(white: 0.8, alpha: 1).setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: tile).cgColor
    }()
}
