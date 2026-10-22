# Milestone 12: Zoom modes and flip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** View › Zoom to Width and Zoom to Height (for tall and wide images, starting at the top or
the leading edge), View › Keep Zoom (zoom and scroll position kept from image to image), and Image ›
Flip Horizontal / Flip Vertical (H / V), written losslessly through the orientation tag like rotate.

**Architecture:** Flips join rotations as an `OrientationChange` that `OrientationRotator` writes
(two more EXIF tables, same temp-file swap); the picture on screen shows changes not yet written
through a `PictureTransform` (mirror plus quarter turns) that replaces `pendingTurns`. Zoom to Width
/ Height are two more `ViewerModel.Zoom` cases that resolve to a zoom factor per image from the fit
area, so they decode through the existing `zoomDecode` path (halving step, `cache` within fit size,
else the one-image `fullSizeCache`) and need no new memory rule. A remembered fit mode (Fit, Width,
Height) is where every new image starts unless Keep Zoom is on; the canvas places a new image at its
start edge, or keeps the relative scroll position under Keep Zoom.

**Tech Stack:** Swift 6, ImageIO, SwiftUI + AppKit (macOS 14+), Core Animation, Swift Testing. No new dependency.

**Spec:** `docs/roadmap.md` "Zoom modes and flip (v2)" (the Mac form, which wins where it differs from
parity), `docs/parity.md` "Zoom modes and flip" and "Display", `docs/spec.md` "Keys", "Toolbar",
"Menu commands", "Rotate", "Languages", "Look". The spec has no section for these yet; Task 5 writes
it from the Decisions below. Rules: `AGENTS.md`.

## Decisions (the roadmap leaves these to the plan)

1. **Zoom to Width / Zoom to Height fill that side of the fit area, small images enlarged** (as the
   reference does), within the zoom range 5 %–1600 %. Why: the mode is for reading a tall screenshot
   or scanning a panorama; a 900 px wide screenshot on a Retina window is 450 pt wide at 100 %, and a
   "never enlarge" rule would leave it a narrow strip, so the command would seem to do nothing on the
   images it exists for. Preview's PDF Zoom to Width enlarges too. Zoom to Fit keeps its rule (never
   enlarges). From 2× on the pixels show sharp, as for any zoom (`ZoomSteps.showsPixels`). The filled
   side is the fit area's (`CanvasInsets.fitArea`: the same 16 pt sides, clear of toolbar and strip,
   beside an open info panel), so a filled picture lines up with a fit one; the other side scrolls
   under the bars like any zoomed picture. Window resize, info panel and full screen refit live.
2. **Start edge.** A new image in Zoom to Width starts at its top (centred sideways when narrower);
   in Zoom to Height at its **leading** edge (centred vertically): the left edge, or the right edge in
   Arabic and Hebrew. The picture never mirrors (spec "Languages"); only where it starts follows the
   reading direction, as the reading side of a right-to-left window is the right. Choosing either
   command on the image shown also goes to that edge (animated as a zoom step, 120 ms, cut under
   Reduce Motion). A new page (⌥→ / ⌥←) counts as a new image.
3. **Fit mode, remembered.** Zoom to Fit (0), Zoom to Width (2) and Zoom to Height (3) set the fit
   mode (`AppSettings.fitMode`, default `fit`, kept across launches as the reference keeps it). Actual
   Size (1), + / − and pinch zoom only the image shown. With Keep Zoom off, every new image (next,
   previous, first, last, after Trash or a move, a page, opening a file or folder, a new window)
   starts in the fit mode at its start edge.
4. **Keep Zoom** (View › Keep Zoom, ⇧L, a checkmark item; `AppSettings.keepZoom`, default **off**,
   remembered): a new image keeps the zoom of the one before, factor or fit mode, and its scroll
   position. One command covers the reference's two toggles (roadmap). It follows the current zoom,
   never a snapshot taken when switched on (parity). Default off as in the reference, Photos and
   Preview, where each image opens fitted. This changes today's behaviour: the viewer now keeps a zoom
   factor from image to image with no setting (see "Decisions needing the maintainer").
5. **Position mapping under Keep Zoom: relative.** The point of the picture at the centre of the clear
   area keeps its fraction of the picture's width and height (0.3 across, 0.8 down stays 0.3 / 0.8),
   then the scroll view clamps it. A same-sized series shows the same pixels; a smaller or larger
   version of the same photo shows the same detail; bottom-right stays bottom-right (parity). This is
   what `ImageCanvas` already does for a new image at a kept zoom, so it stays as is.
6. **Flip Horizontal (H) / Flip Vertical (V)** mirror the picture as shown (left–right / top–bottom),
   whatever its orientation, and write the result losslessly: only the EXIF orientation changes, same
   temp-file swap, same queue as rotate (one change at a time, none lost). Formats and limits exactly
   as rotate: JPEG, HEIC and TIFF; page 1 of a multi-page TIFF; HEIC sequences, GIF, PNG, WebP, RAW,
   PDF, our own formats and every other type are refused with "Lossless flipping works with JPEG,
   HEIC and TIFF only" (rotate's sentence with "flipping"), later TIFF pages with "Only page 1 of
   <name> can be flipped losslessly", a failed write with "Couldn't flip <name>". The reference only
   flips the view (parity); ours writes, like R / L.
7. **Flips show at once, no animation** (the reference and Preview flip instantly); a rotation keeps
   its animated turn (`Theme.Motion.rotation`). The rewritten file's decode then swaps in without a visible change. R on a
   mirrored picture still turns clockwise on screen.
8. **Keys.** H, V, 2, 3 and ⇧L. Checked against every existing single key (spec "Keys": arrows, Space,
   ⌫, Page Up / Down, Home, End, R, L, I, F, Return, Esc, 0, 1, + / = / −, ⌥→ / ⌥←, F7, F8, ⌦, O, B, M,
   P, A, S) and the planned ones (M9 G, M11 F2, M13 T and ⇧⌘T): no clash. H and V are the reference's
   flip keys; ⇧L is its Lock Zoom key. The reference has no key for fit to width / height, so 2 and 3
   continue the 0 / 1 row (digits do nothing in the reference, so switchers lose nothing; on AZERTY
   Shift gives the digit, as for 0 / 1 today). ⇧L must not rotate: `ViewerKey` keeps refusing other
   Shift letters; Caps Lock L (no Shift) is still rotate left. ⌘H (Hide) and ⌘V (Paste) keep their
   menu meaning; the plain letters are separate shortcuts.
9. **Menus.** View, after "Actual Size  (1)": "Zoom to Width  (2)", "Zoom to Height  (3)"; after
   "Zoom Out  (−)" a divider and the toggle "Keep Zoom  (⇧L)". Image, after "Rotate Left  (L)": "Flip
   Horizontal  (H)", "Flip Vertical  (V)". Context menu, after Rotate Right: "Flip Horizontal", "Flip
   Vertical". Enabled as their neighbours (zoom items `hasCurrent`, flips `canChangeFile`; Keep Zoom
   always).
10. **Toolbar.** The default set stays the spec's. Five optional items for View › Customize Toolbar…
    (`.defaultCustomization(.hidden)`): Flip Horizontal (`arrow.left.and.right.righttriangle.left.righttriangle.right`,
    tooltip "Flip horizontal (H)"), Flip Vertical (`arrow.up.and.down.righttriangle.up.righttriangle.down`,
    "Flip vertical (V)"), Zoom to Width (`arrow.left.and.right`, "Zoom to width (2)"), Zoom to Height
    (`arrow.up.and.down`, "Zoom to height (3)"), Keep Zoom (a toggle like Info, `pin`, "Keep zoom (⇧L)").
11. **Decode sizes.** A fill mode is a zoom factor per image (`ZoomSteps.fillFactor`), so it decodes
    at `ImageDecoder.zoomDecode`'s halving step: into the 8-image `cache` when that step is no larger
    than the image's own fit decode (landscape photos in Zoom to Width on a landscape window), else
    into the one-image `fullSizeCache` (portraits in Zoom to Width, panoramas in Zoom to Height).
    Memory stays the existing budget: 8 fit-sized images plus one larger. The price: browsing images
    that need more than their fit decode isn't prefetched (the not-prefetched budget, < 150 ms for a
    12 MP JPEG, applies), as for zoomed browsing today. `shortcut: fill modes beyond fit size prefetch
    nothing, give fullSizeCache a neighbour if browsing tall screenshots in Zoom to Width is common`.
    The fill factor follows the window: a resize re-decodes only when the halving step changes.

## Spike facts (macOS 27, own test files; don't re-measure)

- EXIF orientation after mirroring the **displayed** picture, checked by writing all 8 orientations
  as JPEG, TIFF and HEIC, rewriting with `CGImageDestinationCopyImageSource` +
  `kCGImageDestinationOrientation` (as `OrientationRotator` does) and reading the upright corners back:
  every one correct in all three formats, HEIC included (mirrored values 2, 4, 5, 7 round-trip):

  ```swift
  static let horizontal: [Int: Int] = [1: 2, 2: 1, 3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7]
  static let vertical:   [Int: Int] = [1: 4, 2: 3, 3: 2, 4: 1, 5: 8, 6: 7, 7: 6, 8: 5]
  ```

  The same check confirms the existing `clockwise` table.
- Every orientation is a mirror (or not) after quarter turns clockwise, `M^m ∘ R^t`:
  1 = (no, 0), 2 = (yes, 0), 3 = (no, 2), 4 = (yes, 2), 5 = (yes, 1), 6 = (no, 1), 7 = (yes, 3), 8 = (no, 3).
- SF Symbols: `arrow.left.and.right.righttriangle.left.righttriangle.right` and
  `arrow.up.and.down.righttriangle.up.righttriangle.down` are 2020 symbols (macOS 11), `arrow.left.and.right`,
  `arrow.up.and.down` and `pin` older: all on macOS 14. There is no `flip.vertical`.
- The reference's View › display options list fit to window width / height **without** a key; Lock
  Zoom is Shift+L, Lock Scroll position Ctrl+Shift+K (other fit modes: Shift+O, Shift+W, Shift+F).
- Today a zoom factor already survives next / previous (`setZoom` is the only writer of `zoom`) and the
  canvas keeps the centre's relative position for the new image (`ImageCanvas.updateNSView`, `centre`).

## Where this meets parallel milestones

- **M9 Animation** (its app task is not on main yet): animations are refused by flip (Decision 6), so
  the player never sees a mirror. Its frames decode "at the image's decode target (fit, or the zoom's
  halving step)": in a fill mode that is the step `zoomDecode` picks for the resolved fill factor, so
  whichever lands second makes the player read the model's resolved step, not `case .factor` only.
  G stays M9's.
- **M13 Thumbnail grid:** H, V, 2, 3 and ⇧L do nothing in the grid (`GridKey` maps unlisted keys to
  nil); whichever lands second adds the flip, fill and Keep Zoom menu items to the grid's disabled set
  (M13 Decision 13). Returning from the grid to an image is a new image: fit mode, unless Keep Zoom.
- **M11 Viewer conveniences:** F2 and ⌘N; no overlap.
- All three edit `ViewerKey`, `ViewerModel`, `ViewerView` and the string catalog: rebase, don't redo.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Performance budgets in `AGENTS.md` hold: cold launch < 410 ms and the prefetched swap ≈ 20 ms at the
  default fit mode; Decision 11's not-prefetched case < 150 ms; memory: 8 fit-sized decodes plus one.
- Never lose user data: flips write through a temp file and swap in, like rotate; a failure leaves the
  original untouched.
- Colours, durations only from `Theme.swift`; leading/trailing, never left/right (the canvas's scroll
  view stays left-to-right on purpose; the start edge reads the layout direction).
- Every user-facing string translatable, whole sentences with placeholders; new strings get all 30
  languages (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10): the shared steps").
- Test images come from `Fixtures`, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments, comments describe the code
  as it is; `shortcut:` comments as `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- R after H (or H after R) on a picture already tagged 5–8: the screen must turn and mirror the way
  the file ends up, never the other way round. Pinned in Task 1 (`transformMatchesOrientationTables`
  over every sequence of up to three changes), checked on screen in Task 5.
- H R V L pressed fast while the file is still being rewritten: no change lost, the file ends at the
  composed orientation, the picture never jumps back between decodes. Pinned in Task 1 (the tail of a
  change list is the remaining transform) and Task 3 (`pendingChanges` / `writtenChanges` rules),
  checked in Task 5.
- Zoom to Width on extreme shapes (10 × 20,000, 100,000 × 10) and on a 1 × 1 image: the factor stays in
  5 %–1600 %, the decode never exceeds full size. Pinned in Task 2 (`fillFactorClamps`).
- Keep Zoom off after +, then →: the next image is back in the fit mode at its start edge; Keep Zoom on
  from a bottom-right scroll position onto a smaller image: bottom-right. Pinned in Task 2
  (`startOrigin…`) and Task 4 (`show()` reset rule), checked in Task 5.
- Zoom to Height in Arabic: a panorama starts at its right edge, panning stays physical. Pinned in Task 2
  (`leadingStartIsRightInRightToLeft`), checked in Task 5.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2 | independent Core pieces (orientation changes; zoom rules, keys, settings) |
| B | 3 | flip in the app (uses 1, 2's keys) |
| C | 4 | fill modes and Keep Zoom in the app (uses 2); after 3, which edits the same files and catalog |
| D | 5 (main session) | screen check, budgets, docs |

---

### Task 1: Flips in `OrientationRotator`, and `PictureTransform`

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/OrientationRotator.swift`
- Create: `Sources/FeatherviewCore/Viewer/PictureTransform.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/OrientationRotatorTests.swift`,
  `Tests/FeatherviewCoreTests/Viewer/PictureTransformTests.swift`, `Tests/FeatherviewCoreTests/Fixtures.swift`

**Interfaces:**
- Produces:
  - `public enum Flip: Sendable { case horizontal, vertical }`
  - `public enum OrientationChange: Equatable, Sendable { case rotate(Rotation), flip(Flip) }`
  - `OrientationRotator.next(_ orientation: Int, _ change: OrientationChange) -> Int` — the Spike facts'
    tables for flips, the existing ones for rotations; an unknown value counts as 1.
    `next(_:_ rotation: Rotation)` stays (tests and callers use it).
  - `OrientationRotator.apply(_ link: URL, _ change: OrientationChange, page: Int = 0) throws` — the
    body of today's `rotate`, writing `next(current, change)`; `rotate(_:_:page:)` becomes
    `try apply(link, .rotate(rotation), page: page)`. Same `RotateError`s.
  - `public struct PictureTransform: Equatable, Sendable { var mirrored: Bool; var turns: Int }` —
    `init(_ changes: [OrientationChange] = [])` folds from `(false, 0)`; `var orientation: Int` (the
    EXIF value of the same transform, Spike facts' `M^m ∘ R^t` table, `turns` taken mod 4). `turns` is
    not reduced mod 4, so the canvas animates R R R as three clockwise turns. The fold, pinned because
    the signs are easy to get wrong:

    ```swift
    case .rotate(.clockwise):        turns += mirrored ? -1 : 1
    case .rotate(.counterClockwise): turns += mirrored ? 1 : -1
    case .flip(.horizontal):         mirrored.toggle()
    case .flip(.vertical):           mirrored.toggle(); turns += 2
    ```
  - Fixture `Fixtures.writeQuadrants(to: URL, type: UTType, orientation: Int) throws -> URL` (64 × 32,
    top-leading red, top-trailing green, bottom-leading blue, bottom-trailing white, as in the spike)
    and `Fixtures.corners(of: URL) -> String` ("RG/BW": the upright decode's four corner colours, top
    row then bottom row).

- [ ] **Step 1: Write the failing tests.** `OrientationRotatorTests`: `flipTablesMatchMirroring`
  (`@Test(arguments: 1...8)`: H twice and V twice are identity; H then V equals two clockwise turns);
  `flipsEveryOrientationLosslessly` (arguments: `[UTType.jpeg, .tiff, .heic]` × 1...8 — write quadrants
  at that orientation, `apply(.flip(.horizontal))`, `corners` is the mirror of before ("RG/BW" →
  "GR/WB"; "RB/GW" → "BR/WG"), file size within 200 bytes; same for `.vertical` ("RG/BW" → "BW/RG"));
  `flipRefusesWhatRotateRefuses` (PNG, PNG named `.jpg`, `writeAnimatedGIF`, `writeHEICS` →
  `.unsupportedFormat`, files byte-identical); `flipRefusesLaterTIFFPages` (`writeMultiPageTIFF(pages: 3)`,
  page 1 → `.notFirstPage`); `rotateStillWorks` (existing tests unchanged and passing).
  `PictureTransformTests`: `transformMatchesOrientationTables` (every sequence of 0–3 changes from the six
  `OrientationChange` values: `PictureTransform(seq).orientation == seq.reduce(1, OrientationRotator.next)`);
  `turnsAreNotWrapped` (`[.rotate(.clockwise)] × 3` → turns 3; `[.rotate(.counterClockwise)]` → −1);
  `rotateOnMirroredTurnsBack` (`[.flip(.horizontal), .rotate(.clockwise)]` → mirrored, turns −1);
  `tailIsWhatRemains` (for every sequence and split k: `PictureTransform(Array(seq.dropFirst(k))).orientation`
  applied to `PictureTransform(Array(seq.prefix(k))).orientation` through the tables equals the whole
  sequence's — the rule Task 3 relies on).
- [ ] **Step 2: Run** `swift test --filter "OrientationRotatorTests|PictureTransformTests"` → FAIL (no `Flip`).
- [ ] **Step 3: Implement** the types and tables in the files above; fixtures beside `writeImage`.
- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat: flip horizontally and vertically through the orientation tag, losslessly`

---

### Task 2: Zoom rules, keys and settings

**Files:**
- Modify: `Sources/FeatherviewCore/Viewer/ZoomSteps.swift`, `Sources/FeatherviewCore/Viewer/ViewerKey.swift`,
  `Sources/FeatherviewCore/App/AppSettings.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/ZoomStepsTests.swift`, `ViewerKeyTests.swift`,
  `Tests/FeatherviewCoreTests/App/AppSettingsTests.swift`, `Tests/FeatherviewCoreTests/Imaging/ImageDecoderTests.swift`

**Interfaces:**
- Produces:
  - `public enum FitMode: String, Sendable, CaseIterable { case fit, width, height }`
  - `public enum ZoomStart: Equatable, Sendable { case keep, top, leading }` — where a picture is placed
    when it arrives: `keep` the relative position (Decision 5, also fit, where the clip centres it).
  - `ZoomSteps.fillFactor(image: CGSize, view: CGSize, displayScale: Double, mode: FitMode) -> Double` —
    `.width`: `view.width × displayScale / image.width`; `.height`: the same with heights; clamped to
    `range`; `.fit` returns `fitFactor`; 1 for an empty image or view.
  - `ZoomSteps.startOrigin(_ start: ZoomStart, document: CGSize, clear: CGSize, rightToLeft: Bool) -> CGPoint?`
    — the clear area's top-leading corner in document coordinates (flipped, y down): `.top` →
    `((document.width − clear.width) / 2, 0)`; `.leading` → `(rightToLeft ? document.width − clear.width : 0,
    (document.height − clear.height) / 2)`; nil for `.keep`. Unclamped (the clip view clamps and centres).
  - `ViewerKey` cases `flipHorizontal` ("h"), `flipVertical` ("v"), `zoomToWidth` ("2"), `zoomToHeight`
    ("3"), `toggleKeepZoom` ("l" **with** Shift only). Other Shift letters stay nil.
  - `AppSettings.fitMode = Setting(key: "fitMode", defaultValue: FitMode.fit.rawValue)`,
    `AppSettings.keepZoom = Setting(key: "keepZoom", defaultValue: false)`, registered with the others.

- [ ] **Step 1: Write the failing tests.** `fillWidthEnlarges` (900 × 3000, view 1400 × 800, scale 2 →
  2800 / 900); `fillHeightShrinks` (4000 × 700, view 1400 × 300 at 2 → 600 / 700); `fillFactorClamps`
  (view 1400 × 800, scale 2: 10 × 20,000 width → 16; 100,000 × 10 width → 0.05; 1 × 1 height → 16; zero image → 1);
  `fitModeFitIsFitFactor`; `startOriginTop` (document 2800 × 9000, clear 2800 × 1600 → (0, 0); document
  1000 × 9000 → (−900, 0)); `startOriginLeading` (document 9000 × 1600, clear 2800 × 1600, LTR → (0, 0));
  `leadingStartIsRightInRightToLeft` (same, RTL → (6200, 0)); `keepHasNoOrigin`. In `ImageDecoderTests`,
  pinning Decision 11 with the existing `zoomDecode` (screens `[3024 × 1964]`): `widthFillOfLandscapeStaysInCache`
  (4000 × 3000 at factor 0.7 → `withinFit` true); `widthFillOfPortraitGoesToFullSizeCache` (3024 × 4032 at
  0.93 → step 0, `withinFit` false). `ViewerKeyTests`: `flipKeys` ("h", "v"; "H" with Shift → nil);
  `fillKeys` ("2", "3", and "2" with Shift as AZERTY sends it); `shiftLTogglesKeepZoom` ("L" Shift →
  `.toggleKeepZoom`; "l" → `.rotateLeft`; "L" without Shift (Caps Lock) → `.rotateLeft`; "R" with Shift →
  nil). `AppSettingsTests`: defaults `"fit"` and false.
- [ ] **Step 2: Run** `swift test --filter "ZoomStepsTests|ViewerKeyTests|AppSettingsTests|ImageDecoderTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat: zoom to width and height rules, start edges, keys and settings`

---

### Task 3: Flip in the viewer

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift`, `ImageCanvas.swift`, `ViewerView.swift`
  (keys, Image menu, context menu), `ViewerToolbar.swift` (two optional items), `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 1 holds the logic); `swift build`, bundle, Task 5 on screen.

**Interfaces:**
- Consumes: `OrientationChange`, `Flip`, `OrientationRotator.apply`, `PictureTransform` (1); `ViewerKey.flipHorizontal`
  / `.flipVertical` (2).
- Produces:
  - `ViewerModel.change(_ change: OrientationChange)` — today's `rotate(_:)` generalised; `rotate(_:)`
    and `flip(_ flip: Flip)` call it. Same guard (`canChangeFile`), same `rotateTask` chain, same cache
    drops and `fileRevision` bump. Waits for `Theme.Motion.rotation` before showing the rewritten file
    only for rotations; a flip shows it as soon as it is written (Decision 7).
  - `ViewerModel.pendingChanges: [OrientationChange]` (private(set)) replaces `pendingTurns`;
    `var pendingTransform: PictureTransform { PictureTransform(pendingChanges) }`.
    `writtenTurns` becomes `writtenChanges: (url: URL, count: Int)?`. Rules: a change appends;
    `shown()` of a new decode of the same file drops the first `count` (Task 1's `tailIsWhatRemains`);
    another file clears both; a failed change removes `pendingChanges[written]`, where `written` is
    `writtenChanges.count` for that file, else 0 (earlier changes in the chain were written).
  - Error messages by kind: rotations keep their three strings; flips use Decision 6's three.
  - `ImageCanvas`: `transform: PictureTransform` replaces `turns: Int`. In `ImageLayerView` the image,
    hairline and shadow layers move into one container layer (bounds and position as `place` sets them
    today); the container carries the mirror, `CATransform3DMakeScale(-1, 1, 1)` about its centre, set
    with actions disabled; the quarter turns stay on the sublayers, animated as today. The fit scale for
    odd turns reads `transform.turns`.

- [ ] **Step 1: Implement** the model, canvas, keys (`.flipHorizontal` / `.flipVertical` in `ViewerView.handle`),
  Image menu and context menu items (Decision 9), toolbar items (Decision 10); `swift build`.
- [ ] **Step 2:** `scripts/bundle.sh debug`; `scripts/strings.sh`; the new strings (menu titles, toolbar
  titles and tooltips, three messages) in all 30 languages (shared translation steps);
  `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: Flip Horizontal (H) and Flip Vertical (V) in the viewer`

---

### Task 4: Zoom to Width / Height and Keep Zoom in the viewer

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift`, `ImageCanvas.swift`, `ViewerView.swift`
  (keys, View menu, `drawSize`), `ViewerToolbar.swift` (three optional items), `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 2 holds the rules); `swift build`, bundle, Task 5 on screen.

**Interfaces:**
- Consumes: `FitMode`, `ZoomStart`, `ZoomSteps.fillFactor`, `ZoomSteps.startOrigin`, the `ViewerKey` cases,
  `AppSettings.fitMode` / `.keepZoom` (2).
- Produces:
  - `ViewerModel.Zoom` gains `case fillWidth, fillHeight`; `init(_ mode: FitMode)` and `var start: ZoomStart`
    (`fillWidth` → `.top`, `fillHeight` → `.leading`, else `.keep`). Every existing `zoom == .fit`
    test keeps meaning "decode at fit size"; fill modes take the zoomed path.
  - `ViewerModel.factor(for size: CGSize) -> Double?` — `.factor(f)` → f; fill modes →
    `ZoomSteps.fillFactor(image: size, view: viewSize, displayScale:, mode:)`; `.fit` → nil.
    `zoomDecode`, `setZoom`'s step check, `zoomPercent` and `zoom(by:)` (stepping from a fill mode starts
    from its factor, as from fit) use it instead of matching `case .factor`.
  - `ViewerModel.setFitMode(_ mode: FitMode)` — writes `AppSettings.fitMode`, `setZoom(Zoom(mode))`, bumps
    `arrival` with the mode's start. The 0 key, menu and toolbar Fit call it with `.fit`.
  - `ViewerModel.arrival: (id: Int, start: ZoomStart)` (private(set)) — bumped in `shown()` when the
    decoded image is for another URL or page than the one on screen, with `start` = `.keep` under Keep
    Zoom, else `zoom.start`.
  - Keep Zoom off: `show(page:)` for a URL or page other than the one on screen, and `open(_:)` before it
    picks its prefetch target, set `zoom = Zoom(fitMode)` (from `AppSettings.fitMode`). The model's
    initial `zoom` is `Zoom(fitMode)` too. Rotations and flips re-show the same file: zoom untouched.
  - `viewSize` changes in a fill mode re-run `setZoom(zoom)` so a new halving step re-decodes (no decode
    otherwise).
  - `ImageCanvas` takes `arrival: Int` and `start: ZoomStart`; when `arrival` differs from the last one
    it saw, the scroll target is `ZoomSteps.startOrigin(start, document: size, clear: clearRect.size,
    rightToLeft:)` instead of the centre fraction (the animated path for a fill mode chosen on the same
    image, the cut for a new image). `ViewerView.drawSize` passes the fill factor computed from
    `pixelSize(image)` and `fitArea`, so a smaller decode shown first already has the final size.
  - View menu and keys per Decisions 8–9 (`Toggle` bound to `AppSettings.keepZoom` through `@AppStorage`);
    toolbar items per Decision 10.

- [ ] **Step 1: Implement**; `swift build`.
- [ ] **Step 2:** `scripts/bundle.sh debug`; `scripts/strings.sh`; new strings in all 30 languages;
  `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: Zoom to Width (2), Zoom to Height (3) and Keep Zoom (⇧L)`

---

### Task 5: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folders: the corpus (`swift run -c release
featherview-bench corpus /tmp/fv`, `/tmp/fv/browse`); a mixed folder: 1600 × 900 JPEGs, a 900 × 3000
screenshot PNG, a 4000 × 700 panorama, a 50 × 40 PNG, a 3024 × 4032 portrait, JPEGs tagged with each
of the 8 orientations, a HEIC, a 3-page TIFF, an animated GIF, a QOI file.

- [ ] **Step 1: Check by hand** (release build), light and dark, then in Arabic: H and V on every tagged
  JPEG, then R / L on the flipped ones (each matches Preview's view of the file after); fast H R V L on
  one JPEG (final file as composed); H on page 2 of the TIFF, on the GIF, QOI and PNG (messages, files
  untouched, `cmp` them); ⌘C after a flip (pasted upright and mirrored); Zoom to Width on the
  screenshot (top, filled, enlarged), Zoom to Height on the panorama (leading edge; right edge in
  Arabic); window resize, info panel, full screen and pinch in both modes; the status bar's zoom %;
  Keep Zoom off: + then → back to the fit mode; Keep Zoom on: scroll to bottom-right, → onto a smaller
  image (bottom-right), onto the portrait (same relative spot); fit mode and Keep Zoom remembered after
  ⌘Q; the five optional toolbar items in Customize Toolbar… with their tooltips; menus show 2, 3, ⇧L,
  H, V in the shortcut column; Caps Lock L still rotates.
- [ ] **Step 2: Measure** (`sudo -n /usr/bin/log show`, Instruments' Points of Interest, 5 runs, medians):
  cold launch at the default fit mode (< 410 ms) and with Zoom to Width remembered (note it); `Navigate`
  in Zoom to Width over `/tmp/fv/browse` landscapes (prefetched, ≈ 20 ms) and over portraits (< 150 ms);
  memory after browsing 50 images in each fill mode (8 fit-sized decodes plus one). Fix any miss first.
- [ ] **Step 3: Docs:** `docs/spec.md`: Keys rows for H / V, 2 / 3, ⇧L; "Viewer" bullets for the fill
  modes, start edge, fit mode and Keep Zoom (Decisions 1–5, 11); "Rotate" becomes "Rotate and flip"
  (Decision 6's formats and messages); context menu list; Toolbar's optional items. `docs/parity.md`
  "Zoom modes and flip" rows → Featherview column as built, status `v2`; "Display" fit-modes row → `v2`;
  "Actions" flip row → `v2`. Roadmap: row `| 12 | Zoom modes and flip (v2) |
  docs/superpowers/plans/2026-10-22-milestone-12-zoom-modes-flip.md | done |`. README features line.
- [ ] **Step 4: Commit** `docs: zoom modes and flip done after manual QA`

## Decisions needing the maintainer

Each has a recommendation; the plan is written with it, and a different answer changes one task.

1. **Keep Zoom off by default (Decision 4)**: this changes what the viewer does today (a zoom factor
   now carries over to the next image). Recommendation: off, as in the reference, Photos and Preview,
   where the next image always opens fitted; people who browse zoomed turn Keep Zoom on once and it
   stays on. (Task 4.)
2. **2 and 3 for Zoom to Width / Height (Decision 8)**: the reference has no key for them.
   Recommendation: 2 and 3, next to 0 and 1, which are free in the reference too; otherwise menu only.
   (Task 2.)
3. **Zoom to Height starts at the right edge in Arabic and Hebrew (Decision 2)**. Recommendation: yes,
   the leading edge follows the reading direction, like everything else in a mirrored window, while the
   picture itself never mirrors. (Task 2.)
4. **Fill modes enlarge small images (Decision 1)**: unlike Zoom to Fit. Recommendation: enlarge, as
   the reference and Preview's PDF Zoom to Width do; otherwise the commands seem to do nothing on the
   narrow screenshots they are for. (Task 2.)
