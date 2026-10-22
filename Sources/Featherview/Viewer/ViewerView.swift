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

    private var showsStatusBar: Bool { !statusBarHidden && !model.isFullScreen }
    private var canvasInsets: CanvasInsets {
        .make(toolbarHeight: toolbarHeight, statusBarShown: showsStatusBar, fullScreen: model.isFullScreen,
              infoPanelShown: model.showInfo)
    }

    private func setViewSize(window: CGSize, toolbarHeight: Double) {
        let size = CanvasInsets.make(toolbarHeight: toolbarHeight, statusBarShown: showsStatusBar,
                                     fullScreen: model.isFullScreen, infoPanelShown: model.showInfo).fitArea(in: window)
        if model.viewSize != size { model.viewSize = size }
    }

    private var background: Color { Color(nsColor: Theme.background) }

    /// The picture or what stands for it, with the sheets and messages over it.
    private var canvas: some View {
        ZStack {
            background.ignoresSafeArea()
            if let image = model.image {
                ImageCanvas(image: image, player: model.player, size: drawSize(image), pixelWidth: pixelSize(image).width,
                            displayScale: displayScale, background: Theme.background, insets: canvasInsets, zoom: model.zoom,
                            checkerboard: checkerboard, turns: model.pendingTurns, leaving: model.isLeaving,
                            panController: panController,
                            onDoubleClick: model.toggleFullScreen, onPinch: model.zoom(by:), onSwipe: swiped,
                            onClick: clickedImage,
                            onFirstDraw: { toolbarReady = true; model.firstImageDrawn() },
                            onCommit: model.imageCommitted)
                    .contextMenu { ImageContextMenu(model: model) }
                    // Under the glass toolbar and the status strip; `insets` keeps a fit image clear of them.
                    .ignoresSafeArea()
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
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil {
                Text(message)
                    .messageBox()
                    .padding(.horizontal)
                    .padding(.bottom, canvasInsets.messageBottom)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.isFullScreen, showOverlay, let url = model.list.current {
                Text(OverlayTemplate.render(overlayTemplate, values: overlayValues(url)))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
                    .padding()
            }
        }
    }

    var body: some View {
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
        .overlay(alignment: .bottom) {
            // Nothing to report without a picture: an empty strip is just a grey bar.
            if showsStatusBar, model.image != nil {
                StatusBar(model: model)
                    .padding(.trailing, stripTrailing)
                    .opacity(barsVisible ? 1 : 0)
                    // Opacity only, so Reduce Motion keeps it.
                    .animation(Theme.Motion.fade(barsVisible ? Theme.Motion.barsIn : Theme.Motion.barsOut), value: barsVisible)
            }
        }
        .onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case .active(let point):
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
        .onChange(of: model.chooser != nil || model.destinationPanel != nil || model.showInfo, initial: true) {
            feedAutoHide(.panelOpen($1))
        }
        .onChange(of: barsVisible) { fadeBars(visible: $1) }
        .task(id: hideArm) { await hideBarsAtRest() }
        // On a new image and on entering full screen (double-click, F or Return leave the image as is).
        .onChange(of: model.image) { hidePointerInFullScreen() }
        .onChange(of: model.isFullScreen) { hidePointerInFullScreen() }
        .modifier(ViewerToolbarPlacement(model: model, ready: toolbarReady))
        .onChange(of: toolbarMayBuild, initial: true) { if $1, model.image == nil { ViewerModel.afterFrame { toolbarReady = true } } }
        .toolbar(toolbarHidden || hidesToolbarForFullScreen ? .hidden : .visible, for: .windowToolbar)
        // No hidden toolbar background: the system's scroll edge effect dims a zoomed picture under the toolbar, as in Safari.
        .onChange(of: toolbarHidden, initial: true) { matchTitle() }
        .modifier(RemovesWindowTitle(removed: !toolbarHidden))
        .modifier(ToolbarHiddenInFullScreen())
        .onChange(of: displayScale, initial: true) { model.displayScale = displayScale }
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
            matchTitle()
            // A restored or reopened window may already be in full screen; no didEnter notification follows.
            model.isFullScreen = window.styleMask.contains(.fullScreen)
            if !rememberFrame, !model.isFullScreen { Self.place(window) }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = false }
        }
        // Animations wait while nobody can see them (spec "Animation").
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
            model.player.setVisible(true)
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
            // The main window's model outlives it; a reopened window plays on.
            model.player.setVisible(false)
            if let monitor = autoHide.keyMonitor { NSEvent.removeMonitor(monitor) }
        }
        .onKeyPress(action: handle)
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Fit shrinks large images to the view; a zoom factor scales the file's full pixel size, so a smaller
    /// decode shown while the full one loads already has its final size (never another file's size).
    private func drawSize(_ image: CGImage) -> CGSize {
        let factor: Double? = if case .factor(let factor) = model.zoom { factor } else { nil }
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
        windowSize == .zero ? model.viewSize : canvasInsets.fitArea(in: windowSize)
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
        model.player.setVisible(window.occlusionState.contains(.visible) && !window.isMiniaturized)
    }

    private func hidePointerInFullScreen() {
        if model.isFullScreen, hidePointer { NSCursor.setHiddenUntilMouseMoves(true) }
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
            case .space, .pageDown: model.next(); return .handled
            case Self.backspace, .pageUp: model.previous(); return .handled
            case .home: model.first(); return .handled
            case .end: model.last(); return .handled
            case .deleteForward: model.moveCurrentToTrash(); return .handled
            case Self.f7: model.showDestinations(.move); return .handled
            case Self.f8: model.showDestinations(.copy); return .handled
            case .return: model.toggleFullScreen(); return .handled
            case .escape:
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
        switch action {
        case .rotateRight: model.rotate(.clockwise)
        case .rotateLeft: model.rotate(.counterClockwise)
        case .toggleInfo: model.showInfo.toggle()
        case .toggleFullScreen: model.toggleFullScreen()
        case .fit: model.setZoom(.fit)
        case .actualSize: model.setZoom(.factor(1))
        case .zoomIn: model.zoomIn()
        case .zoomOut: model.zoomOut()
        case .open: model.showOpenPanel()
        case .batch: openWindow(id: "batch")
        case .minimize: model.window?.miniaturize(nil)
        case .settings: SettingsWindow.show()
        case .about: openWindow(id: "about")
        case .saveAs: model.saveAs()
        case .toggleAnimation: model.toggleAnimation()
        case .toggleThumbnails: return .ignored
        case .flipHorizontal, .flipVertical, .zoomToWidth, .zoomToHeight, .toggleKeepZoom: return .ignored
        case .swapImages, .toggleDifference: return .ignored  // compare mode only
        case .slideshow, .playInWindow: break
        }
        return .handled
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
        Button("Copy") { model.copyImage() }
        Divider()
        Button("Rotate Left") { model.rotate(.counterClockwise) }
        Button("Rotate Right") { model.rotate(.clockwise) }
        Divider()
        Button("Move to Folder…") { model.showDestinations(.move) }
        Button("Copy to Folder…") { model.showDestinations(.copy) }
        Button("Move to Trash") { model.moveCurrentToTrash() }
        Divider()
        Button("Show in Finder") { model.showInFinder() }
        OpenWithMenu(model: model)
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
                .disabled(path.isEmpty || model?.availability.hasCurrent != true)
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
            Button("Open…  (O)") { (model ?? ViewerModel.lastActive.current).showOpenPanel() }
                .keyboardShortcut("o")
        }
        // Not replacing .saveItem: SwiftUI shows nothing in that group for an app without documents.
        CommandGroup(after: .newItem) {
            Button("Save As…  (S)") { model?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model?.availability.canChangeFile != true)
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
                Divider()
                // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
                Button("Move to Folder…  (F7)") { model?.showDestinations(.move) }
                Button("Copy to Folder…  (F8)") { model?.showDestinations(.copy) }
                Button("Move to Trash  (⌘⌫ or ⌦)") { model?.moveCurrentToTrash() }
            }
            .disabled(model?.availability.canChangeFile != true)
            Button("Show in Finder") { model?.showInFinder() }
                .disabled(model?.availability.hasCurrent != true)
            OpenWithMenu(model: model)
            if let url = model?.list.current, let type = DefaultViewer.claimableType(for: url) {
                Button("Always Open .\(url.pathExtension.lowercased()) Files with Featherview") {
                    Task { await DefaultViewerOffer.claim(type); claims += 1 }
                }
                .disabled(claims >= 0 && DefaultViewerOffer.opensWithFeatherview(type))
            } else {
                Button("Always Open with Featherview") {}.disabled(true)
            }
            Button("Show Info  (I)") { model?.showInfo.toggle() }
                .disabled(model?.availability.hasCurrent != true)
            Divider()
            Button("Batch Convert…  (B)") { openWindow(id: "batch") }
                .keyboardShortcut("b")
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
        CommandGroup(after: .toolbar) {
            Group {
                Button("Zoom to Fit  (0)") { model?.setZoom(.fit) }
                Button("Actual Size  (1)") { model?.setZoom(.factor(1)) }
                Button("Zoom In  (+)") { model?.zoomIn() }
                Button("Zoom Out  (−)") { model?.zoomOut() }
            }
            .disabled(model?.availability.hasCurrent != true)
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

private extension View {
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
