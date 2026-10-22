import FeatherviewCore
import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @State private var panController = PanController()
    /// Compare's pane 2; arrow keys pan the leading pane's.
    @State private var secondPan = PanController()
    /// The trailing toolbar buttons are built only after the first image (or message) is on screen: building them takes
    /// ~130 ms of the main thread, and in the same update they'd hold back that frame at launch (budget 350 ms).
    @State private var toolbarReady = false
    /// An image or message shows, or none will come. An open that ended with a file current still has its
    /// image on the way (a big folder's first image decodes after the open), and building first delays it.
    private var toolbarMayBuild: Bool {
        model.image != nil || model.errorMessage != nil || model.emptyFolder != nil
            || (!model.isOpening && model.list.current == nil)
    }
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var overlayTemplate = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue
    @AppStorage(AppSettings.thumbnailSize.key) private var thumbnailSize = AppSettings.thumbnailSize.defaultValue
    @AppStorage(AppSettings.sortKey.key) private var sortKey = AppSettings.sortKey.defaultValue
    @AppStorage(AppSettings.sortAscending.key) private var sortAscending = AppSettings.sortAscending.defaultValue
    @AppStorage(toolbarHiddenKey) private var toolbarHidden = false
    @AppStorage(statusBarHiddenKey) private var statusBarHidden = false
    @State private var windowSize = CGSize.zero
    @State private var toolbarHeight = 0.0
    @AppStorage(AppSettings.hideBarsWhileViewing.key) private var hideBars = AppSettings.hideBarsWhileViewing.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// In a box, not @State: pointer moves change its `hideAt`, and re-rendering the viewer on every move costs browsing.
    @State private var autoHide = AutoHideBox()
    @State private var barsVisible = true
    /// Counts each arming of the rest timer: a Bool id could re-arm before SwiftUI saw it go false, and the timer task never restarted.
    @State private var hideArm = 0
    /// The full-screen slideshow capsule: shown on pointer movement, hidden at rest unless the pointer is over it.
    @State private var controlsShown = false
    @State private var controlsHovered = false

    private var showsStatusBar: Bool { !statusBarHidden && !model.isFullScreen }
    private var canvasInsets: CanvasInsets {
        .make(toolbarHeight: toolbarHeight, statusBarShown: showsStatusBar, fullScreen: model.isFullScreen,
              infoPanelShown: model.showInfo)
    }

    private func setViewSize(window: CGSize, toolbarHeight: Double) {
        let insets = CanvasInsets.make(toolbarHeight: toolbarHeight, statusBarShown: showsStatusBar,
                                       fullScreen: model.isFullScreen, infoPanelShown: model.showInfo)
        // While comparing, one pane's: fit and zooming from fit work per pane.
        let size = model.compareSession == nil ? insets.fitArea(in: window)
            : Self.paneInsets(insets).fitArea(in: Self.paneWindow(window))
        if model.viewSize != size { model.viewSize = size }
    }

    /// A compare pane's insets: the window's top and bottom, `CanvasInsets.side` at both sides.
    private static func paneInsets(_ insets: CanvasInsets) -> CanvasInsets {
        CanvasInsets(top: insets.top, bottom: insets.bottom, leading: CanvasInsets.side, trailing: CanvasInsets.side)
    }

    /// One compare pane's share of the window: half of it beside the divider.
    private static func paneWindow(_ window: CGSize) -> CGSize {
        CGSize(width: max(0, (window.width - Theme.compareDivider) / 2), height: window.height)
    }

    private var background: Color { Color(nsColor: Theme.background) }

    /// The picture or what stands for it, with the sheets and messages over it.
    private var canvas: some View {
        ZStack {
            background.ignoresSafeArea()
            if model.isGrid {
                ThumbnailGrid(model: model, urls: model.list.urls, cellSize: thumbnailSize, insets: canvasInsets,
                              hasKeyboard: model.destinationPanel == nil, onKey: gridKey)
                    .ignoresSafeArea()
            } else if let session = model.compareSession {
                ComparePanes(model: model, session: session, first: firstPane, insets: Self.paneInsets(canvasInsets),
                             fitArea: fitArea, displayScale: displayScale, checkerboard: checkerboard,
                             showsStrips: showsStatusBar, stripsVisible: barsVisible, secondPan: secondPan,
                             onSwipe: swiped, onClick: clickedImage)
            } else if let image = model.image {
                imageCanvas(image, insets: canvasInsets)
            } else if let message = model.errorMessage {
                Text(message).messageBox()
            } else if let folder = model.emptyFolder {
                Text("No images in \(folder.lastPathComponent)").messageBox()
            } else if !model.isOpening && model.list.current == nil {
                // Only when nothing is on its way: a loading image shows black, not the hint.
                // Centred in the fit area, not the whole window below the toolbar.
                EmptyHint().padding(fitAreaPadding)
            }
        }
        .overlay { sheets }
        .sheet(item: Binding { model.dateSheet } set: { model.dateSheet = $0 }) { AdjustDateSheet(model: model, sheet: $0) }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil || model.isGrid {
                Text(message)
                    .messageBox()
                    .padding(.horizontal)
                    .padding(.bottom, canvasInsets.messageBottom)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.isFullScreen, showOverlay, !model.isGrid, let url = model.list.current {
                Text(OverlayTemplate.render(overlayTemplate, values: overlayValues(url)))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
                    .padding()
            }
        }
    }

    private func imageCanvas(_ image: CGImage, insets: CanvasInsets, animatesZoom: Bool = true) -> some View {
        ImageCanvas(image: image, player: model.player, size: drawSize(image), pixelWidth: pixelSize(image).width,
                    displayScale: displayScale, background: Theme.background, insets: insets, zoom: model.shownZoom,
                    arrival: model.arrival.id, start: model.arrival.start,
                    checkerboard: checkerboard, transform: model.pendingTransform, leaving: model.isLeaving,
                    panController: panController,
                    onDoubleClick: model.toggleFullScreen, onPinch: model.zoom(by:), onSwipe: swiped,
                    onClick: clickedImage,
                    onFirstDraw: { toolbarReady = true; model.firstImageDrawn() },
                    onCommit: model.imageCommitted, animatesZoom: animatesZoom, compareLink: model.compareLink)
            .contextMenu { ImageContextMenu(model: model) }
            // Under the glass toolbar and the status strip; `insets` keeps a fit image clear of them.
            .ignoresSafeArea()
    }

    /// Compare's pane 1: the viewer's picture, or why it can't show.
    @ViewBuilder private var firstPane: some View {
        if let image = model.image {
            imageCanvas(image, insets: Self.paneInsets(canvasInsets), animatesZoom: false)
        } else if let message = model.errorMessage {
            Text(message).messageBox()
        } else {
            background
        }
    }

    var body: some View {
        canvasWithBars
        .modifier(ViewerToolbarPlacement(model: model, ready: toolbarReady))
        .onChange(of: toolbarMayBuild, initial: true) { if $1, model.image == nil { ViewerModel.afterFrame { toolbarReady = true } } }
        .toolbar(toolbarHidden || hidesToolbarForFullScreen ? .hidden : .visible, for: .windowToolbar)
        // No hidden toolbar background: the system's scroll edge effect dims a zoomed picture under the toolbar, as in Safari.
        .onChange(of: toolbarHidden, initial: true) { matchTitle() }
        .modifier(RemovesWindowTitle(removed: !toolbarHidden))
        .modifier(ToolbarHiddenInFullScreen())
        .onChange(of: displayScale, initial: true) { model.displayScale = displayScale }
        .onChange(of: model.unsaved != nil) { model.window?.isDocumentEdited = $1 }
        .onChange(of: sortKey) { model.applySortOrder() }
        .onChange(of: sortAscending) { model.applySortOrder() }
        // Not set on the window directly: SwiftUI puts the scene's title back on its next update.
        .navigationTitle(model.title)
        .overlay(alignment: .topTrailing) { infoPanel }
        // Here, not a withAnimation at each toggle: I, the toolbar button and the menus all count.
        // The canvas refits on the same curve (ImageCanvas).
        .animation(Theme.Motion.moving(Theme.Motion.panel, reduceMotion: reduceMotion), value: model.showInfo)
        .focusedSceneValue(\.viewer, model)
        .onChange(of: activeState, initial: true) {
            feedAutoHide(.windowKey(activeState == .key))
            guard activeState == .key else { return }
            ViewerModel.lastActive.use(model)
            model.becameActive()
        }
        .background(FirstImageGate(holds: !toolbarMayBuild))
        .background(WindowAccessor { window in
            model.window = window
            CloseGuard.install(on: window, model: model)
            matchTitle()
            // A restored or reopened window may already be in full screen; no didEnter notification follows.
            model.isFullScreen = window.styleMask.contains(.fullScreen)
            if !rememberFrame, !model.isFullScreen { Self.place(window) }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.fullScreenTransitionEnded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.fullScreenTransitionEnded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = false }
        }
        // Animations and the slideshow wait while nobody can see them (spec "Animation").
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { windowShown($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { windowShown($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { windowShown($0) }
        .onReceive(NotificationCenter.default.publisher(for: .AXAnimatedImagesEnabledDidChange)) { _ in
            model.animatedImagesSettingChanged()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: focused, initial: true) { model.hasKeyboardFocus = focused }
        .onAppear {
            focused = true
            ViewerModel.windows.viewerOpened()
            model.setWindowVisible(true)
            // Menu key equivalents (⌘C, ⌥1…) never reach onKeyPress; none of them is a browsing key.
            autoHide.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.window === model.window, !event.modifierFlags.isDisjoint(with: [.command, .control, .option]) {
                    feedAutoHide(.key(browsing: false))
                }
                return event
            }
        }
        .onDisappear {
            ViewerModel.windows.viewerClosed()
            // The main window's model outlives it: the slideshow ends (and lets the display sleep), a reopened
            // window's animation plays on.
            model.endSlideshow()
            model.setWindowVisible(false)
            model.closeWindow()
            if let monitor = autoHide.keyMonitor { NSEvent.removeMonitor(monitor) }
        }
        .onKeyPress(action: handle)
        .frame(minWidth: 480, minHeight: 320)
    }

    /// The canvas with its strip, sizes and bar hiding; `body` adds the window's part. Two chains: as one, Swift 6.3
    /// (CI) can't type-check it in time.
    private var canvasWithBars: some View {
        canvas
        // Not onGeometryChange: it misses the restored window frame at launch, leaving fit at the 100×48 placeholder.
        // The whole window and the toolbar's height (top safe area), so fit and its zoom % use the clear area.
        .background(GeometryReader { geo in
            let window = CGSize(width: geo.size.width,
                                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            Color.clear.onChange(of: [window.width, window.height, geo.safeAreaInsets.top], initial: true) {
                windowSize = window
                toolbarHeight = geo.safeAreaInsets.top
                // Now, not a pass later through the onChange below: the first image waits for it.
                setViewSize(window: window, toolbarHeight: geo.safeAreaInsets.top)
            }
        })
        // Hiding the status bar or entering full screen changes the insets without changing the geometry.
        .onChange(of: canvasInsets) { setViewSize(window: windowSize, toolbarHeight: toolbarHeight) }
        .onChange(of: model.compareSession != nil) { setViewSize(window: windowSize, toolbarHeight: toolbarHeight) }
        .overlay(alignment: .bottom) {
            // Nothing to report without a picture: an empty strip is just a grey bar.
            // While comparing, each pane has its own (ComparePanes).
            if showsStatusBar, model.compareSession == nil, model.image != nil || model.isGrid {
                StatusBar(model: model)
                    .padding(.trailing, stripTrailing)
                    .opacity(barsVisible ? 1 : 0)
                    // Opacity only, so Reduce Motion keeps it.
                    .animation(Theme.Motion.fade(barsVisible ? Theme.Motion.barsIn : Theme.Motion.barsOut), value: barsVisible)
            }
        }
        .overlay(alignment: .bottom) {
            if model.isFullScreen, let state = model.slideshowState {
                SlideshowControls(state: state, previous: { model.previous() }, togglePause: { model.toggleSlideshowPause() },
                                  next: { model.next() }, end: { model.endSlideshowLeavingFullScreen() })
                    .onHover { controlsHovered = $0 }
                    .onDisappear { controlsHovered = false }
                    .opacity(controlsShown ? 1 : 0)
                    .allowsHitTesting(controlsShown)
                    // Opacity only, so Reduce Motion keeps it.
                    .animation(Theme.Motion.fade(controlsShown ? Theme.Motion.barsIn : Theme.Motion.barsOut), value: controlsShown)
                    .padding(.bottom, Theme.slideshowControlsBottom)
            }
        }
        .onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case .active(let point):
                showSlideshowControls()
                let overStrip = showsStatusBar && point.y > windowSize.height - canvasInsets.bottom
                feedAutoHide(.pointerOverBars(point.y < toolbarHeight || overStrip))
                feedAutoHide(point.y < 4 ? .pointerAtTopEdge : .pointerMoved)
            case .ended:
                // Onto the toolbar, which takes the hover, or out of the window: off the picture either way.
                feedAutoHide(.pointerOverBars(true))
            }
        }
        .onChange(of: hideBars, initial: true) { feedAutoHide(.enabled($1)) }
        .onChange(of: model.isFullScreen, initial: true) { feedAutoHide(.fullScreen($1)) }
        .onChange(of: model.image != nil, initial: true) { feedAutoHide(.pictureShown($1)) }
        // The grid keeps its bars like a panel does: the strip holds its slider.
        .onChange(of: model.chooser != nil || model.destinationPanel != nil || model.showInfo || model.isGrid, initial: true) {
            feedAutoHide(.panelOpen($1))
        }
        // The grid's collection view had the keyboard.
        .onChange(of: model.isGrid) { if !$1 { focused = true } }
        // The F7 / F8 panel's keys go through `handle`, not the grid's collection view.
        .onChange(of: model.destinationPanel != nil) { if $1, model.isGrid { focused = true } }
        .onChange(of: barsVisible) { fadeBars(visible: $1) }
        .task(id: hideArm) { await hideBarsAtRest() }
        // On a new image and on entering full screen (double-click, F or Return leave the image as is).
        // A slideshow hides the pointer only at rest, with its capsule.
        .onChange(of: model.image) { if model.slideshowState == nil { hidePointerInFullScreen() } }
        // Paused or finished: the capsule stays up, so a mouse user sees how to go on.
        .onChange(of: [model.slideshowState != .playing, model.isFullScreen]) {
            if model.slideshowState != .playing { showSlideshowControls() }
        }
        .task(id: controlsShown) { if controlsShown { await hideSlideshowControlsAtRest() } }
        .onChange(of: model.isFullScreen) { hidePointerInFullScreen() }
        // A slideshow started inside full screen changes neither of the above, nor shows the capsule.
        .onChange(of: model.slideshowState != nil) { if $1 { hidePointerInFullScreen() } }
    }

    /// Fit shrinks large images to the view; a zoom factor (or a fill mode's, from the fit area) scales the file's
    /// full pixel size, so a smaller decode shown while the full one loads already has its final size (never
    /// another file's size).
    private func drawSize(_ image: CGImage) -> CGSize {
        let factor: Double? = switch model.shownZoom {
        case .fit: nil
        case .factor(let factor): factor
        case .fillWidth: ZoomSteps.fillFactor(image: pixelSize(image), view: fitArea, displayScale: displayScale, mode: .width)
        case .fillHeight: ZoomSteps.fillFactor(image: pixelSize(image), view: fitArea, displayScale: displayScale, mode: .height)
        }
        return ZoomSteps.drawSize(decoded: CGSize(width: image.width, height: image.height), full: fullSize,
                                  factor: factor, view: fitArea, displayScale: displayScale)
    }

    /// The strip ends 16 pt before an open info panel.
    private var stripTrailing: CGFloat {
        model.showInfo ? CanvasInsets.infoPanelSpan - Theme.stripSideInset : 0
    }

    /// Spans the fit area's height, floating on the trailing side (docs/DESIGN.md "Elements").
    @ViewBuilder private var infoPanel: some View {
        if model.showInfo {
            InfoPanel(url: model.list.current, revision: model.fileRevision)
                // Level with the fit area; in full screen (no insets) the panel's own margin.
                .padding(.top, model.isFullScreen ? CanvasInsets.infoPanelMargin : canvasInsets.top - toolbarHeight)
                .padding(.bottom, model.isFullScreen ? CanvasInsets.infoPanelMargin : canvasInsets.bottom)
                .padding(.trailing, CanvasInsets.infoPanelMargin)
                .transition(.offset(x: Theme.Motion.panelTravel).combined(with: .opacity))
        }
    }

    /// The folder chooser and the F7 / F8 panel, centred in the fit area.
    private var sheets: some View {
        ZStack {
            if model.chooser != nil {
                FolderChooserView(model: model).transition(.sheet(reduceMotion: reduceMotion))
            }
            if let operation = model.destinationPanel {
                DestinationPanel(model: model, operation: operation).transition(.sheet(reduceMotion: reduceMotion))
            }
        }
        .padding(fitAreaPadding)
    }

    /// Insets of the safe area that leave the fit area, for things centred in it.
    private var fitAreaPadding: EdgeInsets {
        EdgeInsets(top: canvasInsets.top - toolbarHeight, leading: canvasInsets.leading,
                   bottom: canvasInsets.bottom, trailing: canvasInsets.trailing)
    }

    /// The fit area for the current insets. `model.viewSize` is set in onChange, one render later; the picture
    /// takes its new size in the same render as the new insets, so it refits together with the info panel.
    private var fitArea: CGSize {
        if windowSize == .zero { return model.viewSize }
        if model.compareSession != nil { return Self.paneInsets(canvasInsets).fitArea(in: Self.paneWindow(windowSize)) }
        return canvasInsets.fitArea(in: windowSize)
    }

    /// The file's pixel size, for the current file and page only (never another file's size).
    private var fullSize: CGSize? {
        let info = model.fileInfo
        return info?.isFor(model.list.current, page: model.page) == true ? info?.pixelSize : nil
    }

    /// The pixels `image` stands for, so a smaller decode is smoothed or not as the full one will be.
    private func pixelSize(_ image: CGImage) -> CGSize {
        ZoomSteps.pixelSize(decoded: CGSize(width: image.width, height: image.height), full: fullSize)
    }

    /// shortcut: macOS 14 has no `windowToolbarFullScreenVisibility`, so it still hides the toolbar mid-transition
    /// (the content can stay at the window's old size), drop when macOS 15 is the minimum.
    private var hidesToolbarForFullScreen: Bool {
        if #available(macOS 15, *) { false } else { model.isFullScreen }
    }

    private func windowShown(_ note: Notification) {
        guard let window = model.window, note.object as? NSWindow === window else { return }
        model.setWindowVisible(window.occlusionState.contains(.visible) && !window.isMiniaturized)
    }

    private func hidePointerInFullScreen() {
        if model.isFullScreen, hidePointer { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// Shows the full-screen slideshow capsule and restarts its rest time; kept out of SwiftUI's state, as
    /// re-rendering on every pointer move would cost browsing.
    private func showSlideshowControls() {
        guard model.isFullScreen, model.slideshowState != nil else { return }
        autoHide.controlsHideAt = ProcessInfo.processInfo.systemUptime + BarsAutoHide.rest
        if !controlsShown { controlsShown = true }
    }

    /// Hides the capsule (and, if set, the pointer) after `BarsAutoHide.rest` without movement, unless the pointer
    /// is over it or the slideshow is paused or finished.
    private func hideSlideshowControlsAtRest() async {
        while let hideAt = autoHide.controlsHideAt {
            let now = ProcessInfo.processInfo.systemUptime
            if hideAt > now {
                try? await Task.sleep(for: .seconds(hideAt - now))
                if Task.isCancelled { return }
                continue
            }
            let state = model.slideshowState
            if state != nil, controlsHovered || state != .playing {
                autoHide.controlsHideAt = now + BarsAutoHide.rest
                continue
            }
            autoHide.controlsHideAt = nil
            controlsShown = false
            if state != nil { hidePointerInFullScreen() }
        }
    }

    private func overlayValues(_ url: URL) -> [String: String] {
        var values = ["name": url.lastPathComponent,
                      "folder": url.deletingLastPathComponent().lastPathComponent,
                      "path": OverlayTemplate.path(of: url, home: FileManager.default.homeDirectoryForCurrentUser),
                      "index": "\(model.list.index + 1)", "count": "\(model.list.urls.count)"]
        if let file = model.fileValues, file.url == url { values.merge(file.values) { $1 } }
        return values
    }

    /// A click (or drag) takes the keyboard back and brings hidden bars and the pointer back, as a move does.
    /// A swipe changes images like the arrow it goes the way of (mirrored in right-to-left languages).
    private func swiped(likeRightArrow: Bool) {
        guard !model.isChooserOpen, model.destinationPanel == nil else { return }
        feedAutoHide(.key(browsing: true))
        if ViewerKey.arrowGoesForward(isRightArrow: likeRightArrow, rightToLeft: layoutDirection == .rightToLeft) {
            model.next()
        } else {
            model.previous()
        }
    }

    private func clickedImage() {
        focused = true
        feedAutoHide(.pointerMoved)
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    /// The toolbar's title item shows the name and counter; the window's own title stays for the Window menu
    /// and comes back when the toolbar is hidden or not built yet.
    private func matchTitle() {
        guard #unavailable(macOS 26) else { return }  // RemovesWindowTitle
        model.window?.titleVisibility = toolbarHidden ? .visible : .hidden
    }

    private func feedAutoHide(_ event: BarsAutoHide.Event) {
        autoHide.machine.handle(event, now: ProcessInfo.processInfo.systemUptime)
        if barsVisible != autoHide.machine.barsVisible { barsVisible = autoHide.machine.barsVisible }
        let armed = autoHide.machine.hideAt != nil
        if armed && !autoHide.armed { hideArm &+= 1 }
        autoHide.armed = armed
    }

    /// Sleeps until the machine's `hideAt` (which pointer moves keep pushing back) and sends `.tick`.
    private func hideBarsAtRest() async {
        while let hideAt = autoHide.machine.hideAt {
            let wait = hideAt - ProcessInfo.processInfo.systemUptime
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                continue
            }
            // A context menu or a sheet is open: keep the bars, as for the panels.
            if RunLoop.main.currentMode == .eventTracking || model.window?.attachedSheet != nil {
                feedAutoHide(.pointerMoved)
            } else {
                feedAutoHide(.tick)
            }
        }
    }

    /// The strip fades by its opacity; the toolbar by the titlebar container's alpha, never `.toolbar(.hidden)`,
    /// which would change the layout and move a fit image.
    private func fadeBars(visible: Bool) {
        if let titlebar = model.window?.standardWindowButton(.closeButton)?.superview?.superview {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = visible ? Theme.Motion.barsIn : Theme.Motion.barsOut
                titlebar.animator().alphaValue = visible ? 1 : 0
            }
        }
        if !visible { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// Viewer shortcuts live here, not in the menus: a menu shortcut would also fire while typing
    /// in the Batch window's text fields (⌘⌫ there means "delete to start of line").
    /// The Mac's ⌫ key sends U+007F; SwiftUI's `.delete` is U+0008 and never matches it.
    private static let backspace = KeyEquivalent("\u{7F}")
    private static let f7 = KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!))
    private static let f8 = KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey)!))

    /// Where the next window goes when frames aren't remembered: the first is centred, the rest cascade from it.
    private static var cascadePoint: NSPoint?

    private static func place(_ window: NSWindow) {
        window.setContentSize(NSSize(width: 960, height: 640))
        if let point = cascadePoint {
            cascadePoint = window.cascadeTopLeft(from: point)
        } else {
            window.center()
            cascadePoint = window.cascadeTopLeft(from: .zero)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Arrow keys carry the numeric-pad/function flags and Caps Lock changes nothing here,
        // so only these modifiers count.
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        let rtl = layoutDirection == .rightToLeft
        // Both arrows count, so the right-to-left swap needs nothing extra.
        let browsing = modifiers.isEmpty && [.leftArrow, .rightArrow, .space, Self.backspace, .pageUp, .pageDown,
                                             .home, .end].contains(press.key)
        feedAutoHide(.key(browsing: browsing))
        if model.isChooserOpen { return handleChooser(press, modifiers) }
        if let operation = model.destinationPanel { return handleDestinations(press, modifiers, operation) }
        // The grid's keys, when its collection view hasn't the keyboard (the size slider, Tab); the viewer's keys do
        // nothing there (Decision 13).
        if model.isGrid {
            var gridModifiers: MenuKey.Modifiers = []
            if modifiers.contains(.command) { gridModifiers.insert(.command) }
            if modifiers.contains(.shift) { gridModifiers.insert(.shift) }
            if modifiers.contains(.option) { gridModifiers.insert(.option) }
            if modifiers.contains(.control) { gridModifiers.insert(.control) }
            if let key = GridKey.action(characters: press.characters, modifiers: gridModifiers) { _ = gridKey(key) }
            return .handled
        }
        if modifiers == .option {
            switch press.key {
            case .rightArrow, .leftArrow:
                if ViewerKey.arrowGoesForward(isRightArrow: press.key == .rightArrow, rightToLeft: rtl) {
                    model.nextPage()
                } else {
                    model.previousPage()
                }
                return .handled
            default: return .ignored
            }
        }
        if modifiers == .command, press.key == Self.backspace {
            model.moveCurrentToTrash()
            return .handled
        }
        let panController = model.compareSession?.leader == .second ? secondPan : self.panController
        if modifiers.isEmpty {
            switch press.key {
            case .rightArrow, .leftArrow:
                let isRight = press.key == .rightArrow
                // Panning stays physical; only the step past the edge follows the layout direction.
                if !panController.pan(dx: isRight ? 1 : -1, dy: 0) {
                    if ViewerKey.arrowGoesForward(isRightArrow: isRight, rightToLeft: rtl) { model.next() } else { model.previous() }
                }
                return .handled
            case .downArrow: if !panController.pan(dx: 0, dy: 1) { model.next() }; return .handled
            case .upArrow: if !panController.pan(dx: 0, dy: -1) { model.previous() }; return .handled
            case .space:
                if model.slideshowState != nil { model.toggleSlideshowPause() } else { model.next() }
                return .handled
            case .pageDown: model.next(); return .handled
            case Self.backspace, .pageUp: model.previous(); return .handled
            case .home: model.first(); return .handled
            case .end: model.last(); return .handled
            case .deleteForward: model.moveCurrentToTrash(); return .handled
            case Self.f7: model.showDestinations(.move); return .handled
            case Self.f8: model.showDestinations(.copy); return .handled
            case .return: model.toggleFullScreen(); return .handled
            case .escape:
                // A slideshow first (it leaves full screen too), then compare, then full screen.
                if model.slideshowState != nil { model.endSlideshowLeavingFullScreen(); return .handled }
                if model.compareSession != nil { model.leaveCompare(); return .handled }
                guard model.isFullScreen else { return .ignored }
                model.toggleFullScreen()
                return .handled
            default: break
            }
        }
        // Shift may be needed to type a character key ('+' on US, digits on AZERTY).
        guard modifiers.subtracting(.shift).isEmpty,
              let action = ViewerKey.action(characters: press.characters, shift: modifiers.contains(.shift))
        else { return .ignored }
        return perform(action) ? .handled : .ignored
    }

    /// False: the key does nothing here and goes on up.
    private func perform(_ action: ViewerKey) -> Bool {
        switch action {
        case .rotateRight: model.rotate(.clockwise)
        case .rotateLeft: model.rotate(.counterClockwise)
        case .flipHorizontal: model.flip(.horizontal)
        case .flipVertical: model.flip(.vertical)
        case .toggleInfo: if model.canShowInfo { model.showInfo.toggle() }
        case .toggleFullScreen: model.toggleFullScreen()
        case .fit: model.setFitMode(.fit)
        case .actualSize: model.actualSize()
        case .zoomIn: model.zoomIn()
        case .zoomOut: model.zoomOut()
        case .open: model.showOpenPanel()
        case .batch: openWindow(id: "batch")
        case .minimize: model.window?.miniaturize(nil)
        case .settings: SettingsWindow.show()
        case .about: openWindow(id: "about")
        case .saveAs: model.saveAs()
        case .toggleAnimation: model.toggleAnimation()
        case .toggleThumbnails: model.toggleGrid()
        case .zoomToWidth: model.setFitMode(.width)
        case .zoomToHeight: model.setFitMode(.height)
        case .toggleKeepZoom: UserDefaults.standard.set(!AppSettings.keepZoom.value(), forKey: AppSettings.keepZoom.key)
        case .swapImages:
            guard model.compareSession != nil else { return false }
            model.swapCompared()
        case .toggleDifference: return false  // compare mode only
        case .slideshow:
            if model.slideshowState != nil { model.endSlideshowLeavingFullScreen() } else { model.startSlideshow(fullScreen: true) }
        case .playInWindow:
            if model.slideshowState != nil { model.endSlideshow() } else { model.startSlideshow(fullScreen: false) }
        }
        return true
    }

    /// The grid's keys (its collection view has the keyboard). False: not the grid's, the key goes on up.
    private func gridKey(_ key: GridKey) -> Bool {
        switch key {
        case .view: model.viewFromGrid(model.gridFocus)
        case .toggle: model.toggleGrid()
        case .leave: model.leaveGridCancelling()
        case .larger: model.stepThumbnails(larger: true)
        case .smaller: model.stepThumbnails(larger: false)
        case .passOn(let action): return perform(action)
        case .trash: model.moveCurrentToTrash()
        case .move: model.showDestinations(.move)
        case .copy: model.showDestinations(.copy)
        case .batch:
            guard !model.gridSelection.isEmpty else { return true }
            model.batchSelection()
            openWindow(id: "batch")
        // The collection view's own (ThumbnailGrid): Quick Look needs it as first responder.
        case .quickLook, .first, .last: return false
        }
        return true
    }

    /// While the folder chooser shows, keys drive it and nothing else.
    private func handleChooser(_ press: KeyPress, _ modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isEmpty else { return .handled }
        switch press.key {
        case .upArrow: model.chooserMove(-1)
        case .downArrow: model.chooserMove(1)
        case .space: model.chooserEnter()
        case .rightArrow, .leftArrow:
            let rtl = layoutDirection == .rightToLeft
            if ViewerKey.arrowGoesForward(isRightArrow: press.key == .rightArrow, rightToLeft: rtl) {
                model.chooserEnter()
            } else {
                model.chooserUp()
            }
        case .return: model.chooserOpen()
        case .escape: model.closeChooser()
        default: break
        }
        return .handled
    }

    /// While the F7 / F8 panel shows: a slot key picks a folder, ↑ ↓ and Return use the highlight.
    private func handleDestinations(_ press: KeyPress, _ modifiers: EventModifiers,
                                    _ operation: FileOperation) -> KeyPress.Result {
        guard modifiers.subtracting(.shift).isEmpty else { return .handled }
        switch press.key {
        case .escape: model.destinationPanel = nil
        case .upArrow: model.slots.lastUsed = max(model.slots.lastUsed - 1, 0)
        case .downArrow: model.slots.lastUsed = min(model.slots.lastUsed + 1, DestinationSlots.count - 1)
        case .return: pick(model.slots.lastUsed)
        default:
            if let character = press.characters.first, let slot = DestinationSlots.slot(forKey: character) {
                pick(slot)
            }
        }
        return .handled
    }

    /// An empty slot asks for its folder first.
    private func pick(_ slot: Int) {
        if model.slots[slot] == nil, !model.chooseFolder(for: slot) { return }
        model.transfer(to: slot)
    }
}

struct ImageContextMenu: View {
    let model: ViewerModel

    var body: some View {
        if let state = model.slideshowState {
            Button(state == .playing ? "Pause Slideshow" : "Resume Slideshow") { model.toggleSlideshowPause() }
            Button("End Slideshow") { model.endSlideshowLeavingFullScreen() }
            Divider()
        }
        Button("Copy") { model.copyImage() }
        Divider()
        Button("Rotate Left") { model.rotate(.counterClockwise) }
        Button("Rotate Right") { model.rotate(.clockwise) }
        Button("Flip Horizontal") { model.flip(.horizontal) }
        Button("Flip Vertical") { model.flip(.vertical) }
        Button("Adjust Date Taken…") { model.showAdjustDate() }
        Divider()
        Button("Move to Folder…") { model.showDestinations(.move) }
        Button("Copy to Folder…") { model.showDestinations(.copy) }
        Button("Move to Trash") { model.moveCurrentToTrash() }
        Divider()
        Button("Show in Finder") { model.showInFinder() }
        OpenWithMenu(model: model)
        Divider()
        ShareMenu(model: model)
        Button("Set as Desktop Picture") { model.setDesktopPicture() }
            .disabled(!model.availability.canSetDesktop)
    }
}

/// The apps set in Settings › Open With, by name.
struct OpenWithMenu: View {
    let model: ViewerModel?
    // Observed, so the menu follows Settings › Open With at once.
    @AppStorage(AppSettings.openWith[0].key) private var app1 = ""
    @AppStorage(AppSettings.openWith[1].key) private var app2 = ""
    @AppStorage(AppSettings.openWith[2].key) private var app3 = ""

    var body: some View {
        Menu("Open With") {
            ForEach(0..<3, id: \.self) { index in
                let path = [app1, app2, app3][index]
                Button(path.isEmpty ? String(localized: "App \(index + 1) not set") : FileManager.default.displayName(atPath: path)) {
                    model?.openWith(index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                .disabled(path.isEmpty || model?.availability.hasCurrent != true || model?.isGrid == true)
            }
        }
    }
}

/// Holds the auto-hide machine outside SwiftUI's state (see `ViewerView.autoHide`).
@MainActor private final class AutoHideBox {
    var machine = BarsAutoHide()
    /// Whether `machine.hideAt` was set after the last event (see `ViewerView.hideArm`).
    var armed = false
    var keyMonitor: Any?
    /// When the full-screen slideshow capsule hides (see `ViewerView.showSlideshowControls`).
    var controlsHideAt: Double?
}

/// Reports the hosting window once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Keeps a new window transparent while its first image decodes, so its first frame on screen already shows
/// the picture instead of an empty canvas that fills a few frames later. The decode and the window build still
/// run side by side; the window shows with the image, a message, or after `Theme.Motion.firstImageWait`.
private struct FirstImageGate: NSViewRepresentable {
    let holds: Bool

    func makeNSView(context: Context) -> GateView { GateView(holds: holds) }

    func updateNSView(_ view: GateView, context: Context) { if !holds { view.release() } }

    final class GateView: NSView {
        private var holds: Bool

        init(holds: Bool) {
            self.holds = holds
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        // Before the window's first display: later, its empty frame would already be on screen.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard holds, let window, !window.isVisible else { holds = false; return }
            window.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.firstImageWait) { [weak self] in self?.release() }
        }

        func release() {
            guard holds else { return }
            holds = false
            window?.alphaValue = 1
        }
    }
}

extension FocusedValues {
    /// The viewer of the focused window; menu commands act on it.
    @Entry var viewer: ViewerModel?
}

/// The info panel (I): file name and format, then the fields in a grouped card (docs/DESIGN.md "Elements").
struct InfoPanel: View {
    let url: URL?
    /// Changes when the file is rewritten (rotation), so the fields are read again.
    let revision: Int
    @State private var fields: [MetadataField] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelGap) {
            HStack(spacing: Theme.panelGap) {
                Text(verbatim: url?.lastPathComponent ?? "")
                    .font(Theme.panelHeader)
                    .foregroundStyle(Theme.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let format = url.flatMap({ UTType(filenameExtension: $0.pathExtension)?.preferredFilenameExtension }) {
                    Text(verbatim: format.uppercased())
                        .font(Theme.badge)
                        .foregroundStyle(Theme.labelSecondary)
                        .padding(Theme.footerKeyCapPadding)
                        .background(Theme.badgeFill, in: .rect(cornerRadius: Theme.Radius.small))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.badgeLine, lineWidth: 1))
                }
            }
            .frame(height: Theme.infoHeaderHeight)
            .padding(.horizontal, Theme.infoHeaderPadding)
            if !fields.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                            if index > 0 {
                                Theme.rowSeparator.frame(height: 1).padding(.leading, Theme.rowPadding)
                            }
                            HStack(spacing: Theme.panelGap) {
                                Text(field.label).font(Theme.row).foregroundStyle(Theme.labelPrimary)
                                Spacer(minLength: 0)
                                Text(verbatim: field.value)
                                    .font(Theme.rowValue)
                                    .foregroundStyle(Theme.labelSecondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(minHeight: Theme.infoRowHeight)
                            .padding(.horizontal, Theme.rowPadding)
                        }
                    }
                    .background(Theme.cardFill, in: .rect(cornerRadius: Theme.Radius.group))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.group).strokeBorder(Theme.cardLine, lineWidth: 1))
                }
                .scrollIndicators(.automatic)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.infoPanelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(.panel, cornerRadius: Theme.Radius.panel)
        // Reads the file off the main thread.
        .task(id: "\(revision) \(url?.path ?? "")") {
            guard let url else { return fields = [] }
            let read = await Task.detached { MetadataReader.fields(for: url) }.value
            if !Task.isCancelled { fields = read }
        }
        .textSelection(.enabled)
    }
}

/// Whether viewer windows hide their toolbar (View › Hide Toolbar).
private let toolbarHiddenKey = "toolbarHidden"
/// Whether viewer windows hide their status bar (View › Hide Status Bar).
private let statusBarHiddenKey = "statusBarHidden"

/// Only the main window's toolbar is customizable. AppKit copies every item inserted into a customizable
/// toolbar into all windows with that toolbar's id, so a second window adding its buttons after its first
/// image (or page buttons for a PDF) crashed with "already contains an item". Extra windows show the same
/// buttons at once instead (the main window waits for the launch budget, see `toolbarReady`).
private struct ViewerToolbarPlacement: ViewModifier {
    let model: ViewerModel
    let ready: Bool

    func body(content: Content) -> some View {
        if model === ViewerModel.main {
            content.toolbar(id: "viewer") { ViewerToolbar(model: model, ready: ready) }
        } else {
            content.toolbar { ViewerToolbar(model: model, ready: true) }
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(toolbarHiddenKey) private var toolbarHidden = false
    @AppStorage(statusBarHiddenKey) private var statusBarHidden = false
    @AppStorage(AppSettings.keepZoom.key) private var keepZoom = AppSettings.keepZoom.defaultValue
    /// Bumped after a claim, so the menu asks LaunchServices again for the current file's type.
    @State private var claims = 0

    private func showInAbout(_ text: String?) {
        AboutSheet.shared.text = text
        openWindow(id: "about")
    }

    var body: some Commands {
        // Built at launch even when no window is restored (the last one was closed or minimized): a file
        // opened from Finder then still gets the main window, which otherwise waited for a window's view.
        let _ = OpensViewerWindows.install(openWindow)
        CommandGroup(replacing: .appInfo) {
            Button("About Featherview  (A)") { openWindow(id: "about") }
            Button("Check for Updates…") { Task { await Updater.check(manual: true) } }
        }
        CommandGroup(replacing: .help) {
            Button("Featherview Website") { NSWorkspace.shared.open(AboutInfo.website) }
            Button("Source Code") { NSWorkspace.shared.open(AboutInfo.repository) }
            Divider()
            Button("Supported Formats") { showInAbout(AboutView.formatsText) }
            if let url = AboutView.licenseURL {
                Button("MIT License") { showInAbout(try? String(contentsOf: url, encoding: .utf8)) }
            }
            if let url = AboutView.acknowledgementsURL {
                Button("Acknowledgements") { showInAbout(try? String(contentsOf: url, encoding: .utf8)) }
            }
            Divider()
            Button("Report a Bug…") { NSWorkspace.shared.open(AboutView.bugReportURL) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.show() }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            ClipboardCommand(model: model)
            Button("Open…  (O)") { (model ?? ViewerModel.lastActive.current).showOpenPanel() }
                .keyboardShortcut("o")
            RecentMenu()
            Button("Compare With…") { model?.showCompareOpenPanel() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(model?.availability.canCompare != true)
            if model?.compareSession != nil {
                Button("Stop Comparing") { model?.leaveCompare() }
            }
        }
        // Not replacing .saveItem: SwiftUI shows nothing in that group for an app without documents.
        CommandGroup(after: .newItem) {
            Button("Save As…  (S)") { model?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model?.availability.canChangeFile != true && model?.unsaved == nil)
            Divider()
            ShareMenu(model: model)
        }
        CommandGroup(replacing: .pasteboard) {
            // Text fields and selected text (batch window, Info panel) keep their own Copy and Paste.
            Button("Copy") {
                // Selected text in the Info panel isn't an NSText, but it takes SwiftUI focus from the viewer.
                if let model, model.hasKeyboardFocus, !(NSApp.keyWindow?.firstResponder is NSText) {
                    model.copyImage()
                } else {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("c")
            // The grid has no image to copy and no text field (Decision 13).
            .disabled(model?.isGrid == true)
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a")
        }
        CommandMenu("Image") {
            // Disabled as the toolbar buttons are, so menu and toolbar agree.
            Button("Next  (→ or Space)") { model?.next() }
                .disabled(model?.availability.canGoForward != true)
            Button("Previous  (← or ⌫)") { model?.previous() }
                .disabled(model?.availability.canGoBack != true)
            Group {
                if model?.isAnimation == true {
                    Button("Next Frame  (⌥→)") { model?.nextPage() }
                    Button("Previous Frame  (⌥←)") { model?.previousPage() }
                } else {
                    Button("Next Page  (⌥→)") { model?.nextPage() }
                    Button("Previous Page  (⌥←)") { model?.previousPage() }
                }
            }
            .disabled(model?.availability.hasPages != true)
            Button(model?.player.isPlaying == true ? "Pause Animation  (G)" : "Play Animation  (G)") { model?.toggleAnimation() }
                .disabled(model?.isAnimation != true)
            Divider()
            Group {
                Button("Rotate Right  (R)") { model?.rotate(.clockwise) }
                Button("Rotate Left  (L)") { model?.rotate(.counterClockwise) }
                Button("Flip Horizontal  (H)") { model?.flip(.horizontal) }
                Button("Flip Vertical  (V)") { model?.flip(.vertical) }
            }
            .disabled(model?.availability.canChangeFile != true)
            // Also on the grid's selection, as Photos does (Decision 8).
            Button("Adjust Date Taken…") { model?.showAdjustDate() }
                .disabled(model?.canAdjustDate != true)
            Divider()
            Group {
                // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
                Button("Move to Folder…  (F7)") { model?.showDestinations(.move) }
                Button("Copy to Folder…  (F8)") { model?.showDestinations(.copy) }
                Button("Move to Trash  (⌘⌫ or ⌦)") { model?.moveCurrentToTrash() }
            }
            // The viewed image, or the grid's selection.
            .disabled(model?.operationTargets.isEmpty != false)
            // In the grid these would act on the image viewed before T, not the cells (Decision 13).
            Button("Show in Finder") { model?.showInFinder() }
                .disabled(model?.availability.hasCurrent != true || model?.isGrid == true)
            OpenWithMenu(model: model)
            Button("Set as Desktop Picture") { model?.setDesktopPicture() }
                .disabled(model?.availability.canSetDesktop != true)
            if let url = model?.list.current, model?.isGrid != true, let type = DefaultViewer.claimableType(for: url) {
                Button("Always Open .\(url.pathExtension.lowercased()) Files with Featherview") {
                    Task { await DefaultViewerOffer.claim(type); claims += 1 }
                }
                .disabled(claims >= 0 && DefaultViewerOffer.opensWithFeatherview(type))
            } else {
                Button("Always Open with Featherview") {}.disabled(true)
            }
            Button("Show Info  (I)") { model?.showInfo.toggle() }
                .disabled(model?.canShowInfo != true)
            if model?.isGrid == true {
                // The two selected cells, in list order.
                Button("Compare") {
                    if let model, model.gridSelection.count == 2 { model.compare(model.gridSelection[0], with: model.gridSelection[1]) }
                }
                .disabled(model?.gridSelection.count != 2)
            }
            Divider()
            Button("Batch Convert…  (B)") {
                // In the grid the selection joins the batch's list.
                if model?.isGrid == true { model?.batchSelection() }
                openWindow(id: "batch")
            }
            .keyboardShortcut("b")
            .disabled(model?.isGrid == true && model?.gridSelection.isEmpty == true)
        }
        // Not ToolbarCommands: SwiftUI shows its toolbar at every launch, so whether it's hidden is kept here.
        CommandGroup(replacing: .toolbar) {
            Button(toolbarHidden ? "Show Toolbar" : "Hide Toolbar") { toolbarHidden.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Customize Toolbar…") {
                NSApp.sendAction(#selector(NSWindow.runToolbarCustomizationPalette(_:)), to: nil, from: nil)
            }
            .disabled(model == nil || toolbarHidden)
            Button(statusBarHidden ? "Show Status Bar" : "Hide Status Bar") { statusBarHidden.toggle() }
        }
        CommandGroup(before: .windowList) {
            Toggle("Float on Top", isOn: Binding(get: { model?.isFloating == true }, set: { model?.isFloating = $0 }))
                .disabled(model == nil || model?.isFullScreen == true)
        }
        CommandGroup(after: .toolbar) {
            Button(model?.isGrid == true ? "Show Image  (T)" : "Show Thumbnails  (T)") { model?.toggleGrid() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model?.availability.canShowGrid != true)
            if model?.compareSession != nil {
                Button("Swap Images  (X)") { model?.swapCompared() }
                    .disabled(model?.availability.canSwap != true)
                Toggle("Zoom and Pan in Step", isOn: Binding(get: { model?.compareInStep == true },
                                                              set: { model?.setCompareInStep($0) }))
            }
            Group {
                Button("Zoom to Fit  (0)") { model?.setFitMode(.fit) }
                Button("Actual Size  (1)") { model?.actualSize() }
                Button("Zoom to Width  (2)") { model?.setFitMode(.width) }
                Button("Zoom to Height  (3)") { model?.setFitMode(.height) }
            }
            .disabled(model?.availability.hasPicture != true || model?.isGrid == true)
            // In the grid + and − size the thumbnails (Decision 5).
            if model?.isGrid == true {
                Button("Larger Thumbnails  (+)") { model?.stepThumbnails(larger: true) }
                Button("Smaller Thumbnails  (−)") { model?.stepThumbnails(larger: false) }
            } else {
                Group {
                    Button("Zoom In  (+)") { model?.zoomIn() }
                    Button("Zoom Out  (−)") { model?.zoomOut() }
                }
                .disabled(model?.availability.hasPicture != true)
            }
            Divider()
            Toggle("Keep Zoom  (⇧L)", isOn: $keepZoom)
                .disabled(model?.isGrid == true)
            Divider()
            SortMenu()
            Divider()
            let playing = model?.slideshowState != nil
            Group {
                Button(playing ? "End Slideshow  (W)" : "Start Slideshow  (W)") {
                    if playing { model?.endSlideshowLeavingFullScreen() } else { model?.startSlideshow(fullScreen: true) }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(playing ? "Stop Playing  (⇧A)" : "Play in Window  (⇧A)") {
                    if playing { model?.endSlideshow() } else { model?.startSlideshow(fullScreen: false) }
                }
            }
            .disabled(!playing && model?.availability.canStartSlideshow != true)
            if let state = model?.slideshowState {
                Button(state == .playing ? "Pause Slideshow  (Space)" : "Resume Slideshow  (Space)") {
                    model?.toggleSlideshowPause()
                }
            }
            SlideshowOptionsMenu(model: model)
        }
    }
}

/// View › Slideshow Options: a submenu, so it can be changed mid-show from the menu bar.
private struct SlideshowOptionsMenu: View {
    let model: ViewerModel?
    @AppStorage(AppSettings.slideshowSeconds.key) private var seconds = AppSettings.slideshowSeconds.defaultValue
    @AppStorage(AppSettings.slideshowShuffle.key) private var shuffle = AppSettings.slideshowShuffle.defaultValue
    @AppStorage(AppSettings.slideshowRepeat.key) private var repeats = AppSettings.slideshowRepeat.defaultValue

    /// Stores the choice, then tells the running slideshow, which reads it back from the settings.
    private func binding<Value>(_ value: Binding<Value>) -> Binding<Value> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; model?.slideshowOptionsChanged() })
    }

    var body: some View {
        Menu("Slideshow Options") {
            Picker("Show Each Image For", selection: binding($seconds)) {
                ForEach(Slideshow.intervals, id: \.self) { seconds in
                    Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))).tag(seconds)
                }
            }
            Toggle("Shuffle", isOn: binding($shuffle))
            Toggle("Repeat", isOn: binding($repeats))
        }
    }
}

/// The empty window: the feather, what to do, and the keys for it, on an 18 pt glass card (docs/DESIGN.md "Elements").
private struct EmptyHint: View {
    var body: some View {
        VStack(spacing: Theme.emptyCardGap) {
            FeatherMark(size: Theme.featherSize)
            Text("Open an image or drop a folder here")
                .font(Theme.hintText)
                .foregroundStyle(Theme.labelHint)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.keyCapGap) {
                KeyCap(key: "⌘O")
                KeyCap(key: "O")
            }
        }
        .padding(Theme.emptyCardPadding)
        .frame(width: Theme.emptyCard.width, height: Theme.emptyCard.height)
        // Flat on the canvas, not floating: there's nothing under it for glass to lift off.
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.cardLine))
    }
}

extension View {
    /// Readable over the background and over the picture.
    func messageBox() -> some View {
        padding(Theme.messagePadding).glass(.card, cornerRadius: Theme.Radius.message)
    }
}

/// The window's own title gives way to the toolbar's title item on macOS 26, where SwiftUI shows it again on
/// each update if only the window's `titleVisibility` is changed (ViewerToolbar's flexible space takes its place).
/// Optional kind: no change of view identity.
private struct RemovesWindowTitle: ViewModifier {
    let removed: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.toolbar(removing: removed ? .title : nil) } else { content }
    }
}

/// Full screen hides the toolbar the native way: it slides in with the menu bar when the pointer is at the top.
/// Hiding it with `.toolbar(.hidden)` from willEnterFullScreen left the content at the old window size (View menu)
/// or kept the toolbar's strip as a black band (Return).
struct ToolbarHiddenInFullScreen: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.windowToolbarFullScreenVisibility(.onHover) } else { content }
    }
}
