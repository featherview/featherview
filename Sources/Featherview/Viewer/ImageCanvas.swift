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
func moveVisibleOrigin(_ scrollView: NSScrollView, to point: CGPoint) {
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

extension NSScrollView {
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
    /// Its frames show in place of `image` (frame 0) once playback moves.
    var player: AnimationPlayer?
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
    /// A change places the picture at `start` (Zoom to Width at its top, Zoom to Height at its leading edge):
    /// a cut for a new image, animated for a fit mode chosen on the one shown. `.keep` keeps the relative position.
    var arrival = 0
    var start = ZoomStart.keep
    let checkerboard: Bool
    /// Mirror and quarter turns to show the picture with (R, L, H, V before the file is rewritten): turns animate
    /// about its centre, a mirror shows at once.
    var transform = PictureTransform()
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
    /// False in compare: two panes animating apart would drift, so zoom steps are cuts there.
    var animatesZoom = true
    /// In compare: pans this pane in step with the other one.
    var compareLink: CompareLink? = nil
    var pane: CompareSession.Pane = .first
    /// A sharp decode of a part of a huge picture, laid over `image`; `rect` in full-size pixels.
    var region: (image: CGImage, rect: CGRect)? = nil
    /// `image` is the fit picture enlarged under `region`'s parts: smoothed at any zoom.
    var byParts = false
    /// The file's pixel size, for placing `region` and reporting the visible rect; nil while unknown.
    var fullPixelSize: CGSize? = nil
    /// The visible part of the picture in full-size pixels, after each scroll and update.
    var onVisibleRect: (CGRect) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Reports the visible rect while the clip view scrolls.
    @MainActor final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        var fullPixelSize: CGSize?
        var onVisibleRect: (CGRect) -> Void = { _ in }

        @objc func boundsChanged(_ note: Notification) { report() }

        /// The clear area within the document, scaled to full-size pixels; nothing while a zoom animates (its
        /// completion reports), as a mid-zoom rect covers much more than the settled view.
        func report() {
            guard let scrollView, let fullPixelSize, let document = scrollView.documentView as? ImageLayerView,
                  document.targetSize.map({ $0 == document.frame.size }) ?? true else { return }
            let bounds = document.bounds
            let visible = scrollView.clearRect.intersection(bounds)
            guard bounds.width > 0, bounds.height > 0, !visible.isEmpty else { return }
            let sx = fullPixelSize.width / bounds.width, sy = fullPixelSize.height / bounds.height
            onVisibleRect(CGRect(x: visible.minX * sx, y: visible.minY * sy, width: visible.width * sx, height: visible.height * sy))
        }
    }

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
        // A picture pans diagonally, not locked to the axis the fingers started on.
        scrollView.usesPredominantAxisScrolling = false
        scrollView.documentView = ImageLayerView()
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scrollView
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        panController.scrollView = scrollView
        scrollView.backgroundColor = background
        guard let view = scrollView.documentView as? ImageLayerView else { return }
        let coordinator = context.coordinator
        coordinator.fullPixelSize = fullPixelSize
        coordinator.onVisibleRect = onVisibleRect
        // After every return below: a resize or a new picture moves the visible rect without a scroll.
        defer { coordinator.report() }
        player?.onFrame = { [weak view] in view?.showFrame($0) }
        let image = player?.current ?? image
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
        view.onFirstDraw = onFirstDraw
        view.onCommit = onCommit
        let canvas = scrollView as? CanvasScrollView
        canvas?.onPinch = onPinch
        canvas?.onSwipe = onSwipe
        compareLink?.register(scrollView, as: pane)
        canvas?.onLead = { [weak compareLink, pane] in compareLink?.lead(pane) }
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
        let startPoint = view.arrival == arrival ? nil
            : ZoomSteps.startOrigin(start, document: size, clear: scrollView.clearRect.size, rightToLeft: rtl)
        view.arrival = arrival
        let animate = animatesZoom && view.shows(image) && (zoomChanged || panelRefit || startPoint != nil) && pinch == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.zoom = zoom
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sameImage = view.shows(image)
        let showsPixels = ZoomSteps.showsPixels(drawnWidth: size.width, imageWidth: Int(pixelWidth), displayScale: displayScale)
        view.show(image, checkerboard: checkerboard && image.hasAlpha,
                  smooth: ZoomSteps.smoothsPicture(drawnWidth: size.width, imageWidth: Int(pixelWidth),
                                                   displayScale: displayScale, byParts: byParts))
        view.showRegion(region, fullPixelSize: fullPixelSize, smooth: !showsPixels)
        // A fit picture turned a quarter ends at the size it will fit at, not overflowing.
        let clearSize = CGSize(width: scrollView.contentView.bounds.width - contentInsets.left - contentInsets.right,
                               height: scrollView.contentView.bounds.height - contentInsets.top - contentInsets.bottom)
        let turnScale = zoom == .fit && transform.turns % 2 != 0 && size.width > 0 && size.height > 0
            ? min(1, clearSize.width / size.height, clearSize.height / size.width) : 1
        // A flip shows at once, also the half turn a vertical one carries.
        let flipped = view.mirror(transform.mirrored)
        view.turn(to: transform.turns, scale: turnScale, animated: sameImage && !reduceMotion && !flipped)
        if leaving, sameImage { view.fadeOut() }
        // The size last asked for, not the frame: mid-animation the frame is part-way, and a new image
        // at the same zoom must leave the running animation alone.
        let resized = view.targetSize != size
        view.targetSize = size
        // E3 shadow and hairline only while the picture fits the clear area (a transparent one would show it through).
        let clear = scrollView.contentView.bounds.size
        // Fit fits by definition: at launch the first image arrives before the clip is laid out (zero
        // bounds), and measured, it showed without its shadow until the next update.
        let fits = zoom == .fit || size.width <= clear.width - contentInsets.left - contentInsets.right + 0.5
            && size.height <= clear.height - contentInsets.top - contentInsets.bottom + 0.5
        let framed = fits && (!image.hasAlpha || checkerboard)
        // Off at the first frame beyond fit; on once a zoom back into fit has landed.
        if !framed || !(animate && (resized || insetsChanged)) { view.setFramed(framed) }
        if resized || insetsChanged || startPoint != nil {
            let clip = scrollView.contentView
            cut { view.animator().setFrameSize(size) }
            let visible = scrollView.clearRect
            let offset = pinch == nil ? CGPoint(x: visible.width / 2, y: visible.height / 2)
                : CGPoint(x: anchor.x - oldVisible.minX, y: anchor.y - oldVisible.minY)
            let point = startPoint ?? CGPoint(x: centre.x * size.width - offset.x, y: centre.y * size.height - offset.y)
            guard animate else {
                moveVisibleOrigin(scrollView, to: point)
                compareLink?.resized(pane)
                return
            }
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
                view.animateShadows(from: oldSize, to: size, duration: context.duration, timing: context.timingFunction)
            } completionHandler: {
                MainActor.assumeIsolated {
                    scrollView.reflectScrolledClipView(clip)
                    if framed, view.targetSize == size { view.setFramed(true) }
                    coordinator.report()
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
    /// The user moved this canvas (scroll, pinch, click): in compare it leads the other pane.
    var onLead: () -> Void = {}
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
        onLead()
        pinch = (event.locationInWindow, event.timestamp)
        onPinch(1 + event.magnification)
    }

    /// Three-finger swipes, when the trackpad is set to swipe between pages with three fingers.
    override func swipe(with event: NSEvent) {
        if event.deltaX != 0 { onSwipe(event.deltaX < 0) }
    }

    override func scrollWheel(with event: NSEvent) {
        onLead()
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
    /// The canvas's `arrival` last placed; nil before the first update.
    var arrival: Int?
    /// Holds the picture, its shadow and hairline, and carries the mirror; the quarter turns are on its sublayers.
    private let pictureLayer = CALayer()
    private let imageLayer = CALayer()
    /// A sharp part of a huge picture over the enlarged fit picture; a sublayer of `imageLayer`, so turns and the mirror apply.
    private let regionLayer = CALayer()
    private var region: (image: CGImage, rect: CGRect)?
    private var fullPixelSize: CGSize?
    /// The E3 elevation's contact and ambient shadows and the picture hairline, while the picture fits.
    private let shadowLayers = Theme.Elevation.e3.layers.map { _ in CALayer() }
    private let hairline = CALayer()
    private var framed = false
    private var shownTurns = 0
    private var mirrored = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        pictureLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Shadows and hairline follow an animated zoom like the picture does.
        for layer in shadowLayers + [hairline] { layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable] }
        for shadow in shadowLayers.reversed() { pictureLayer.addSublayer(shadow) }
        hairline.borderWidth = 1
        pictureLayer.addSublayer(hairline)
        pictureLayer.addSublayer(imageLayer)
        regionLayer.contentsGravity = .resize
        // Scales with the picture during an animated zoom within the same step.
        regionLayer.autoresizingMask = [.layerMinXMargin, .layerWidthSizable, .layerMaxXMargin,
                                        .layerMinYMargin, .layerHeightSizable, .layerMaxYMargin]
        regionLayer.isHidden = true
        imageLayer.addSublayer(regionLayer)
        layer?.addSublayer(pictureLayer)
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

    /// Grows or shrinks the shadows with a zoom: a shadow path doesn't follow its layer's bounds, so without
    /// this they jump to the new size while the picture still animates to it.
    func animateShadows(from old: CGSize, to new: CGSize, duration: TimeInterval, timing: CAMediaTimingFunction?) {
        guard framed else { return }
        for layer in shadowLayers {
            let animation = CABasicAnimation(keyPath: "shadowPath")
            animation.fromValue = CGPath(rect: CGRect(origin: .zero, size: old), transform: nil)
            animation.toValue = CGPath(rect: CGRect(origin: .zero, size: new), transform: nil)
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: "zoom")
        }
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

    /// Mirrors the picture left–right about its centre (or back), without animation; true when that changed.
    func mirror(_ on: Bool) -> Bool {
        guard on != mirrored else { return false }
        mirrored = on
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.transform = on ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        CATransaction.commit()
        return true
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

    /// An animation's next frame: same size and look as the one before, no update of the rest, not a commit
    /// the `Navigate` signpost waits for.
    func showFrame(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }

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
        place(pictureLayer)
        place(imageLayer)
        // Below 2× smooth; from 2× on, show the pixels.
        imageLayer.magnificationFilter = smooth ? .linear : .nearest
        imageLayer.minificationFilter = .trilinear
        layer?.backgroundColor = checkerboard ? Self.checkerColor : nil
        CATransaction.commit()
    }

    /// Lays `region` (full-size pixels) over the picture, or hides it when nil.
    func showRegion(_ region: (image: CGImage, rect: CGRect)?, fullPixelSize: CGSize?, smooth: Bool) {
        self.region = region
        self.fullPixelSize = fullPixelSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Below 2× smooth; from 2× on, show the pixels.
        regionLayer.magnificationFilter = smooth ? .linear : .nearest
        placeRegion()
        CATransaction.commit()
    }

    private func placeRegion() {
        guard let region, let full = fullPixelSize, full.width > 0, full.height > 0 else {
            regionLayer.isHidden = true
            regionLayer.contents = nil  // a dropped part isn't kept in memory
            return
        }
        if (regionLayer.contents as AnyObject?) !== region.image { regionLayer.contents = region.image }
        let sx = imageLayer.bounds.width / full.width, sy = imageLayer.bounds.height / full.height
        regionLayer.frame = CGRect(x: region.rect.minX * sx, y: region.rect.minY * sy,
                                   width: region.rect.width * sx, height: region.rect.height * sy)
        regionLayer.minificationFilter = imageLayer.minificationFilter
        regionLayer.isHidden = false
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(pictureLayer)
        place(imageLayer)
        placeRegion()
        if framed { layoutFrameLayers() }
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        (enclosingScrollView as? CanvasScrollView)?.onLead()
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

    /// Grey and white squares behind transparent images.
    private static let checkerColor: CGColor = {
        let side = Theme.checkerTile
        let tile = NSImage(size: NSSize(width: 2 * side, height: 2 * side), flipped: false) { rect in
            Theme.checkerDark.setFill()
            rect.fill()
            Theme.checkerLight.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            NSRect(x: side, y: side, width: side, height: side).fill()
            return true
        }
        return NSColor(patternImage: tile).cgColor
    }()
}
