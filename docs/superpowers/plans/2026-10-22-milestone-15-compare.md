# Milestone 15: Compare images — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** Two images side by side in the viewer window, zoomed and panned in step, with next / previous
stepping the first pane, swap, and a difference view; started with a second image chosen in an open
panel (or, once milestone 13 is in, from two selected thumbnails).

**Architecture:** Compare is a mode of the viewer window, like M13's grid. The first pane *is* the viewer
as it is today (`ViewerModel`'s list, `show()`, caches, prefetch, keys); the second pane is a small
`CompareSession` holding one more file, decoded through the viewer's own 8-image cache. Core gets the
pure mapping between two pictures of different pixel sizes (`CompareSync`) and the difference image
(`ImageDifference`, Core Image, off the main thread). The app shows two `ImageCanvas`es in an `HStack`
(so right-to-left mirrors the order) and a `CompareLink` that copies the pan of the pane the user moves
to the other one.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSScrollView`, `NSOpenPanel`), Core Image
(`CIFilter.differenceBlendMode`), ImageIO, Swift Testing. No new dependency.

**Spec:** `docs/roadmap.md` "Compare images (v2)" (scope and Mac form; it wins where it differs from
parity), `docs/parity.md` "Compare images" (the reference's behaviour), `docs/spec.md` "Viewer", "Keys",
"Mouse and trackpad", "Look", `docs/DESIGN.md`. The spec has no compare section yet; Task 7 writes one
from the Decisions below. Rules: `AGENTS.md`.

## Decisions (the roadmap leaves these to the plan; accepted by the maintainer)

1. **A mode of the viewer window, not its own window.** Mac users compare in a mode of the same
   window (Photos' and Lightroom's compare views, Preview's side-by-side pages); "in step" needs both
   pictures under one set of keys; two tiled windows can't stay in step (roadmap). File › "Compare
   With…" (⌥⌘O) opens an open panel (same types as Open…, starting in the current image's folder,
   message "Choose an image to compare with <name>"); the chosen file becomes the second pane. Chosen
   again while comparing, it replaces the second image. Disabled without a current image. From M13's
   grid: `ViewerModel.compare(_:with:)` on two selected thumbnails (Task 4 Step 4 or Task 7, whichever
   finds the grid on main).
2. **Layout:** two panes of equal width, the first at the leading side (an `HStack`, so it is on the right
   in right-to-left languages), a 1 pt divider in `Theme.separator`. Each pane is its own canvas (the
   picture never mirrors, as today), fits between the toolbar and its own floating status strip, with
   `CanvasInsets.side` at both sides of each pane. The window never resizes. The info panel closes on
   entering; I does nothing (menu item disabled). Each pane's strip: name · pixel size · zoom · file size ·
   date; the position stays in the title.
3. **Title:** "<first> and <second>" (`CompareText.title`), then pane 1's counter as today.
4. **In step (View › "Zoom and Pan in Step", on by default, remembered).** Content-aligned, not
   pixel-for-pixel: the second picture is drawn at `CompareSync.matchedFactor` — the first's factor × s,
   s = min(w₁/w₂, h₁/h₂) of the displayed (orientation-applied) pixel sizes — so it covers the box the
   first is drawn in, centred, and the same detail sits at the same place in both panes. Same pixel size
   (the common case: a burst, two edits of one photo): exactly pixel for pixel at the same zoom. An image
   and its resized batch copy: they line up, which the same-zoom rule can't do. At fit, pane 1 fits as
   today and pane 2 matches it, so a smaller second image is drawn enlarged (its strip shows its own
   zoom %). Pan: whichever pane the user scrolls, drags or pinches is the leader; the other follows
   (`CompareSync.followerCentre`). Zoom keys, the toolbar's zoom buttons, 0, 1 and pinch zoom pane 1's
   factor (`model.zoom`), pane 2 follows. Zoom steps are cuts in compare (no 120 ms animation): two
   animations would drift apart. Matched factors are clamped to `ZoomSteps.range`; at the clamp the panes
   stop lining up (shortcut comment).
5. **In step off:** each pane keeps its own zoom (pane 2's starts at `.fit`) and pan; zoom keys, 0, 1 and
   pinch act on the pane last clicked, scrolled or pinched (pane 1 at first). Turning it on again snaps
   pane 2 to pane 1.
6. **Stepping:** → ← Space ⌫ Page Up/Down Home End, the toolbar's arrows and swipes step pane 1 through
   the viewer's list as today (past-the-end rules and the folder chooser unchanged); pane 2 stays. Zoom
   and the relative scroll position stay (the canvas already keeps the relative centre across a resize).
   Arrow keys pan the leader first when it has something to pan, as today.
7. **Swap:** X, View › "Swap Images  (X)" and a button on pane 2's strip (`arrow.left.arrow.right`,
   tooltip "Swap Images (X)") exchange the files: pane 1 shows the second file (selected in the list when
   it's there, else the window opens its folder and stays in compare), pane 2 the first. Zoom stays.
   Disabled while pane 2 can't open.
8. **Difference:** D and View › "Show Difference  (D)" (a checkmark item) show |first − second| per
   channel (R, G, B) in pane 2, both flattened over black, no amplification. The second is scaled by s and
   centred in the first's decoded pixel box (the same mapping as Decision 4); outside it the first shows
   through. Computed with Core Image off the main thread from the two decodes on screen, at the first's
   decoded size; recomputed when either decode changes (a step, a swap, a zoom past a decode step);
   superseded results are dropped. Pane 2 then draws it exactly as pane 1 draws its picture (same size and
   scroll position); its strip reads "Difference". Off while pane 2 can't open. Stays on across steps and swaps.
9. **Leaving:** Esc (in full screen the first Esc leaves compare, the second leaves full screen, as M13's
   grid does), File › "Stop Comparing", the close button on pane 2's strip (`xmark`, tooltip "Stop
   Comparing (Esc)"), opening a file or folder into the window (⌘O, drop, Finder), T (M13's grid), and the
   list running empty (the last image trashed). Pane 1's image stays at its zoom; pane 2's decodes go.
10. **What acts on which pane:** every command on "the current image" (R / L, ⌘C, S, F7 / F8, Trash, page
    keys, Show in Finder, Open With, Always Open…) acts on pane 1, unchanged. Pane 2 shows page 1 and,
    for animations, frame 0 (a still).
11. **Memory:** pane 2's decode at fit size goes in the viewer's 8-image cache (target `.fit(screens)`, so
    a swap or a step onto that file reuses it); beyond fit, its zoom decode goes in a 1-image cache that
    exists only while comparing; plus one difference image at pane 1's decoded size. Pane 2's file joins
    the decode window right after the current image (`[current, second] + neighbours`), so a held arrow
    key never drops its decode. Worst case on top of today: one fit image held by pane 2 after the LRU let
    it go, one zoom decode, one difference image.
12. **Errors:** pane 2 unreadable or gone: "Can't open <name>" (the existing string) in pane 2's area,
    compare stays (choose another, or leave). Comparing a file with itself is allowed.

## Spike facts (macOS 27, M1 Pro, own test images; don't re-measure)

- `CIFilter.differenceBlendMode()` with `inputImage` = first, `backgroundImage` = second scaled and
  translated, composited over `CIImage(color: .black)` cropped to the first's extent, rendered with
  `CIContext.createCGImage(_:from:format: .RGBA8, colorSpace:)`: identical → (0, 0, 0); 100 × 100 red vs a
  50 × 50 half red scaled ×2 → (127, 0, 0) everywhere; 200 × 100 white vs 100 × 100 white centred →
  white outside the covered middle, black inside.
- Time, 4032 × 3024 vs 4032 × 3024: first render 36–49 ms (context warm-up), then 5 ms; vs a 2016 × 1512
  second: 21–24 ms first, 6 ms after. GPU and software renderer alike. Keep one `CIContext` for the app.

## Performance budgets for compare (Task 7 measures them; a regression is a bug)

| Budget | Target | Why |
|---|---|---|
| Open panel's Open to the second picture on screen | < 150 ms for a 12 MP JPEG | The viewer's not-prefetched budget; one fit decode. Signpost `CompareShow`. |
| Stepping pane 1, prefetched | unchanged: `Navigate` p50 ≈ 20 ms | Pane 2 isn't touched; its file is already in the decode window. |
| Stepping pane 1, not prefetched | < 150 ms | Today's budget. |
| D, or a step with the difference on, to the difference on screen | < 100 ms after both decodes (12 MP) | 5–50 ms measured. Signpost `Difference`. |
| Memory | Decision 11 | |
| Cold launch | unchanged (< 410 ms) | No compare object exists until compare starts. |

## Where this meets parallel milestones

- **M13 Thumbnail grid:** the grid's two-thumbnail start calls `ViewerModel.compare(_ first: URL, with
  second: URL)` (first = the earlier one in list order) and leaves the grid; T leaves compare. Neither
  plan waits: whichever lands second wires it (Task 4 Step 4 if `ViewerModel.isGrid` exists, else
  Task 7 checks again). M13's Task 2 adds `ImageList.select(_:) -> Bool`; Task 1 here adds the same
  signature only if it isn't on main yet.
- **M12 Zoom modes, Keep Zoom:** compare doesn't need it: the zoom factor already survives a step and the
  canvas keeps the relative centre. If Keep Zoom is on main, compare leaves it alone.
- **M9 Animation:** pane 2 is always a still (frame 0). While the difference shows, it is computed from
  pane 1's decoded still, never from playback frames; if M9's player is on main, Task 6 pauses pane 1's
  playback while the difference shows.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency (Core Image is a system framework).
- Performance budgets in `AGENTS.md` hold, plus the table above. Decoding and the difference never run
  on the main thread.
- Colours, radii, metrics, durations only from `Theme.swift`; leading/trailing, never left/right.
- Every user-facing string translatable, whole sentences with placeholders (`String(localized:)` outside
  SwiftUI literals); new strings get all 30 languages (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10): the shared steps").
- Test images come from `Fixtures` or are drawn in the test, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- Two pictures of different sizes and shapes (4000 × 3000 vs its 1000 × 750 copy; landscape vs portrait;
  an EXIF-rotated JPEG): in step they line up, never pan to different places. Pinned in Task 1
  (`resizedCopyMatches`, `differentAspectFitsInsideBox`, `followerCentreSameSizeIsIdentity`,
  `followerCentreOffsetsByHalfTheDifference`), checked in Task 7 with the rotated file.
- Feedback between the two scroll views (each bounds change triggering the other): no ping-pong, no drift
  after a fling, a pinch or a zoom step. Pinned in Task 5 (leader-only propagation, a re-entrancy flag),
  checked in Task 7 by flinging both panes.
- Holding → through a folder while pane 2 is zoomed past fit: pane 2 never goes blank or re-decodes
  (its file stays in the decode window). Pinned in Task 4 (`focusDecodes` puts it at rank 1), checked in Task 7.
- The difference of transparent PNGs, an HDR HEIC and a grey-scale image against an RGB one: black where
  they match, no crash, no colour shift. Pinned in Task 2 (`alphaFlattensOverBlack`,
  `greyAgainstRGB`), checked in Task 7 with an HDR file.
- Pane 2's file trashed or moved in Finder, or pane 1's last image trashed: "Can't open" in pane 2, swap
  and difference disabled; an empty list leaves compare. Pinned in Task 4 (Rules), checked in Task 7.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2, 3 | independent Core pieces (mapping; difference image; texts, keys, setting) |
| B | 4 | compare mode in the window (uses 1, 3) |
| C | 5, 6 | pan in step and the toggle (uses 4); the difference view (uses 2, 4). Both touch `ViewerView.swift`'s View menu at different items; merge 5 first |
| D | 7 (main session) | screen check, budgets, docs |

---

### Task 1: Mapping between the two pictures

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/CompareSync.swift`
- Modify: `Sources/FeatherviewCore/Viewer/ImageList.swift` (`select`, only if not on main)
- Test: `Tests/FeatherviewCoreTests/Viewer/CompareSyncTests.swift`, `ImageListTests.swift`

**Interfaces:**
- Produces:
  - `public enum CompareSync`
    - `static func scale(first: CGSize, second: CGSize) -> Double` — `min(first.w / second.w, first.h / second.h)`;
      1 when either size is empty.
    - `static func matchedFactor(_ firstFactor: Double, first: CGSize, second: CGSize) -> Double` —
      `firstFactor × scale`, clamped to `ZoomSteps.range` (`// shortcut: at the clamp the panes stop lining
      up, clamp pane 1's zoom to the pair's range if people zoom that far`).
    - `static func followerCentre(_ leaderCentre: CGPoint, leaderDrawn: CGSize, followerDrawn: CGSize) -> CGPoint`
      — the leader's clear-area centre in its document (points) to the follower's:
      `leaderCentre + (followerDrawn − leaderDrawn) / 2` per axis (both pictures centred in one box).
  - `ImageList.select(_ url: URL) -> Bool` — makes `url` current (drops a held image); false and
    unchanged when not listed (M13's signature).

- [ ] **Step 1: Write the failing tests:** `sameSizeScaleIsOne`; `resizedCopyMatches` (first 4000 × 3000 at
  factor 0.25, second 1000 × 750 → 1.0, both drawn 1000 × 750 px); `differentAspectFitsInsideBox`
  (first 4000 × 3000, second 3000 × 4000 → scale 0.75); `emptySizeScaleIsOne`;
  `matchedFactorClamps` (0.05, 4000 × 3000 vs 8000 × 6000 → 0.05; 16, 1000 × 750 vs 100 × 75 → 16);
  `followerCentreSameSizeIsIdentity` ((300, 200), 800 × 600 both → (300, 200));
  `followerCentreOffsetsByHalfTheDifference` ((400, 300), leader 800 × 600, follower 450 × 600 →
  (225, 300); and back: (225, 300), leader 450 × 600, follower 800 × 600 → (400, 300));
  `selectMakesCurrent`, `selectUnknownIsFalse` in `ImageListTests` (skip both if M13 already added them).
- [ ] **Step 2: Run** `swift test --filter "CompareSyncTests|ImageListTests"` → FAIL (no `CompareSync`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat: map zoom and pan between two pictures of different sizes`

---

### Task 2: The difference image

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/ImageDifference.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/ImageDifferenceTests.swift`

**Interfaces:**
- Consumes: `CompareSync.scale` (Task 1; if run in parallel, the same one-line formula, and the merge keeps Task 1's).
- Produces: `public enum ImageDifference` —
  `static func make(_ first: CGImage, _ second: CGImage, colorSpace: CGColorSpace?) throws -> CGImage`:
  first's pixel size, RGBA8 in `colorSpace` (sRGB when nil); second scaled by `CompareSync.scale` and
  centred; both composited over black; `CIFilter.differenceBlendMode()`; rendered by one shared
  `CIContext` (a `static let`, created on first use, never at launch). Throws
  `ImageDifference.Failure.render` when Core Image returns nil.
  Synchronous; callers run it off the main thread. Signpost interval `Difference` around the render.

- [ ] **Step 1: Write the failing tests** (images drawn with `CGContext` in the test):
  `identicalIsBlack` (100 × 100 (51, 102, 153) twice → every sampled pixel (0, 0, 0));
  `redAgainstHalfRed` (255 vs 128 red → (127 ± 1, 0, 0));
  `smallerSecondIsScaled` (100 × 100 red vs 50 × 50 half red → width 100, pixel (50, 50) is (127 ± 1, 0, 0));
  `differentAspectShowsFirstOutside` (200 × 100 white vs 100 × 100 white → (5, 50) white, (100, 50) black);
  `alphaFlattensOverBlack` (fully transparent 10 × 10 vs opaque black → black);
  `greyAgainstRGB` (DeviceGray 50 % vs sRGB (128, 128, 128) → each channel ≤ 2);
  `resultIsEightBitRGBA` (`bitsPerComponent == 8`, `width`/`height` of the first).
- [ ] **Step 2: Run** `swift test --filter ImageDifferenceTests` → FAIL.
- [ ] **Step 3: Implement** (the spike's pipeline above).
- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat: per-pixel difference of two images with Core Image`

---

### Task 3: Compare texts, keys and the in-step setting

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/CompareText.swift`
- Modify: `Sources/FeatherviewCore/Viewer/StatusLine.swift`, `ViewerKey.swift`,
  `Sources/FeatherviewCore/App/AppSettings.swift`, `Resources/Localizable.xcstrings`
- Test: `Tests/FeatherviewCoreTests/Viewer/CompareTextTests.swift`, `StatusLineTests.swift`, `ViewerKeyTests.swift`

**Interfaces:**
- Produces:
  - `CompareText.title(first: String, second: String) -> String` — "\(first) and \(second)".
  - `CompareText.choose(_ name: String) -> String` — "Choose an image to compare with \(name)".
  - `CompareText.difference: String` — "Difference".
  - `StatusLine.pane(name: String, pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?, modified: Date?) -> StatusLine`
    — name, then the same size, zoom, bytes and date fields `make` writes (no position, page or frame).
  - `ViewerKey.swapImages` on "x", `ViewerKey.toggleDifference` on "d" (Shift: nothing, as other letters).
    The view ignores both outside compare.
  - `AppSettings.compareInStep = Setting(key: "compareInStep", defaultValue: true)`.

- [ ] **Step 1: Write the failing tests:** `titleNamesBoth`; `chooseNamesTheFile`; `paneFieldsInOrder`
  (name, "4,032 × 3,024", "25%", size, date under `Locale(identifier: "en")`; nil values left out);
  `xSwapsDTogglesDifference` and `shiftXIsNothing` in `ViewerKeyTests`; `compareInStepDefaultsOn`.
- [ ] **Step 2: Run** `swift test --filter "CompareTextTests|StatusLineTests|ViewerKeyTests|AppSettingsTests"` → FAIL.
- [ ] **Step 3: Implement;** `scripts/strings.sh`; the new keys in all 30 languages (shared translation steps).
- [ ] **Step 4: Run** the same filter plus `StringCatalogTests|LocalizableCatalogTests` → PASS.
- [ ] **Step 5: Commit** `feat: texts, keys and setting for comparing images`

---

### Task 4: Compare mode in the viewer window

**Files:**
- Create: `Sources/Featherview/Viewer/CompareSession.swift` (the second pane's state),
  `Sources/Featherview/Viewer/ComparePanes.swift` (the two canvases, divider and strips)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (enter, leave, swap, decode, title, availability,
  `open(_:keepingCompare:)`, `focusDecodes`), `ViewerView.swift` (panes instead of the canvas, keys, menus),
  `StatusBar.swift` (a pane variant), `Sources/Featherview/Design/Theme.swift` (`compareDivider = 1` in metrics),
  `Sources/FeatherviewCore/Imaging/Signposts.swift` only if names are constants there (`CompareShow`)
- Test: none new in Core (Tasks 1 and 3 hold the logic); `swift build`, bundle, Task 7 on screen.

**Interfaces:**
- Consumes: `CompareSync.matchedFactor`, `ImageList.select` (1); `CompareText`, `StatusLine.pane`,
  `ViewerKey.swapImages`, `AppSettings.compareInStep` (3).
- Produces (Tasks 5 and 6 build on these):
  - `@MainActor @Observable final class CompareSession` — `enum Pane { case first, second }`;
    `private(set) var url: URL`; `var image: CGImage?`; `var info: FileInfo?`; `var errorMessage: String?`;
    `var leader: Pane = .first`; `var ownZoom: ViewerModel.Zoom = .fit` (Task 5); `var showsDifference = false`,
    `var difference: CGImage?` (Task 6); `let zoomCache: ImageCache` (capacity 1, the viewer's queue).
  - `ViewerModel`: `private(set) var compareSession: CompareSession?`; `func compare(_ first: URL, with second: URL)`
    (selects `first` in the list or opens it keeping compare, then shows `second`);
    `func showCompareOpenPanel()`; `func leaveCompare()`; `func swapCompared()`;
    `var secondZoom: Zoom` (in step: `.factor(CompareSync.matchedFactor(pane 1's factor — fit factor of the
    pane's `viewSize` when `.fit` —, first: fileInfo pixel size, second: session.info pixel size))`; off: `ownZoom`);
    `func showSecond()` (decodes `session.url` for `secondZoom`); `availability.canCompare`, `canSwap`.
  - `func open(_ url: URL, keepingCompare: Bool = false)` — the existing open; `false` leaves compare.

Rules:
- `showSecond()`: target `.fit(screens)` in `cache` when `ImageDecoder.zoomDecode(…).withinFit` (or
  `secondZoom == .fit`), else `.step(step)` in `session.zoomCache`; off the main thread like `show()`;
  stale results (URL or zoom changed meanwhile) dropped; signpost `CompareShow` from the call to the
  commit; log line "compare <name>: <ms> ms". Re-run when pane 1's image (its pixel size) or zoom
  changes and the needed decode differs.
- `focusDecodes()` while comparing: `decodes.focus([current, session.url] + neighbours)`.
- `viewSize` while comparing is one pane's fit area (`CanvasInsets.fitArea` of the pane), so `.fit` and
  `zoom(by:)` from fit work per pane.
- Entering closes the info panel; leaving drops the session (its `zoomCache` with it). `open(_:)` with
  `keepingCompare == false`, an empty list after a removal, and Esc / "Stop Comparing" / the strip's
  close button call `leaveCompare()`. Esc order: compare, then full screen.
- `swapCompared()`: `let first = list.current`; the session's URL becomes `first`; then
  `list.select(second) ? show() : open(second, keepingCompare: true)`; `showSecond()`. Disabled while
  `session.errorMessage != nil`.
- `ComparePanes`: `HStack(spacing: 0)` of pane 1 (`ImageCanvas` with `model.image`, as today), a
  `Theme.separator` divider `Theme.compareDivider` wide, pane 2 (`ImageCanvas` with `session.image`,
  `size` from `ZoomSteps.drawSize(…, factor: secondZoom's factor …)`, or the error message box); each with
  a `StatusBar` showing `StatusLine.pane` (pane 2's strip adds the swap and close buttons, `Theme`
  symbol sizes, tooltips per Decision 7 and 9). Insets per pane: toolbar top, strip bottom,
  `CanvasInsets.side` both sides. Pane 2's canvas gets its own `PanController`; arrow keys pan the leader's.
- Menus: File › "Compare With…" (⌥⌘O) after Open…, "Stop Comparing" while comparing; View ›
  "Swap Images  (X)" while comparing; Image › "Show Info  (I)" disabled while comparing. Title per Decision 3.
  Context menu on pane 2: Swap Images, Stop Comparing, Show in Finder (pane 2's file).
- Zoom in compare is a cut: `ImageCanvas` gets `var animatesZoom = true`, passed `false` by both panes
  (folded into its `animate` condition).

- [ ] **Step 1: Implement** the session, the model API and Rules, the panes, menus and keys; `swift build`.
- [ ] **Step 2:** `scripts/bundle.sh debug`; `scripts/strings.sh`; new menu titles and tooltips in all 30
  languages; `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: compare two images side by side in the viewer window`
- [ ] **Step 4 (only if `ViewerModel.isGrid` exists on main):** the grid's Image menu gets "Compare"
  (enabled with exactly two selected), calling `compare(first, with: second)` in list order and leaving
  the grid; T while comparing leaves compare first. `swift build`, strings in 30 languages, commit
  `feat: compare two selected thumbnails`.

---

### Task 5: Pan in step, and the toggle

**Files:**
- Create: `Sources/Featherview/Viewer/CompareLink.swift`
- Modify: `Sources/Featherview/Viewer/ImageCanvas.swift` (register with the link, report the leader,
  follow), `ComparePanes.swift`, `ViewerModel.swift` (zoom routing when not in step), `ViewerView.swift`
  (View › "Zoom and Pan in Step")
- Test: none new in Core (Task 1 holds the mapping); Task 7 on screen.

**Interfaces:**
- Consumes: `CompareSync.followerCentre` (1); `CompareSession.leader`, `ownZoom`, `secondZoom` (4).
- Produces:
  - `@MainActor final class CompareLink` — `func register(_ scrollView: NSScrollView, as pane: CompareSession.Pane)`;
    `var inStep: Bool`; `var onLeader: (CompareSession.Pane) -> Void`; `func follow(_ pane: CompareSession.Pane)`
    (positions that pane's clip from the other's current clear-area centre).
  - `ImageCanvas`: `var compareLink: CompareLink? = nil`, `var pane: CompareSession.Pane = .first`.
  - `ViewerModel.setCompareInStep(_ on: Bool)` (writes `AppSettings.compareInStep`; on: `ownZoom` ignored,
    pane 2 snaps, `follow(.second)`).

Rules:
- Each pane's clip view sets `postsBoundsChangedNotifications = true`; the link observes both. A change
  on the **leader's** clip, while `inStep` and not already applying, maps its clear-area centre through
  `followerCentre` (drawn sizes = the two documents' frame sizes) and sets the follower's origin with the
  canvas's `moveVisibleOrigin` (constrained by `CenteringClipView`); a flag set while applying stops the
  echo. Changes on the follower's clip are never propagated.
- The leader becomes the pane that gets `scrollWheel`, `magnify`, `mouseDown` (`CanvasScrollView`,
  `ImageLayerView`); it is reported through `onLeader` into `session.leader`.
- After each `updateNSView` resize, the follower calls `link.follow(pane)` so the order SwiftUI updates
  the two canvases in never matters.
- In step off: zoom keys, 0, 1, toolbar zoom and pinch go to the leader's zoom (`model.zoom` for `.first`,
  `session.ownZoom` for `.second`, then `showSecond()`); no pan propagation.

- [ ] **Step 1: Implement**; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh` ("Zoom and Pan in Step" in all 30 languages); `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: zoom and pan both compared images in step`

---

### Task 6: The difference view

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`toggleDifference`, recompute), `CompareSession.swift`,
  `ComparePanes.swift` (pane 2 shows the difference), `ViewerView.swift` (D key, View › "Show Difference  (D)")
- Test: none new in Core (Task 2 holds the image); Task 7 on screen.

**Interfaces:**
- Consumes: `ImageDifference.make` (2); `ViewerKey.toggleDifference`, `CompareText.difference` (3);
  `CompareSession.showsDifference`, `difference`, `image`, `model.image` (4).
- Produces: `ViewerModel.toggleDifference()`; `availability.canShowDifference` (comparing, both images decoded,
  pane 2 without error).

Rules:
- Recompute when `showsDifference` turns on and whenever `model.image` or `session.image` changes while on:
  `LatestWins.submit` a job that runs `ImageDifference.make(first, second, colorSpace: screen space)` in a
  detached task (`.userInitiated`) and assigns `session.difference` only if both images are still the ones
  it was made from. Until it lands, pane 2 keeps the previous difference (no flash to the second image).
- Pane 2 while on: `ImageCanvas` with `session.difference`, pane 1's draw size, zoom, `pixelWidth` and
  turns; the link keeps the two in step regardless of the toggle (identical drawn sizes → identity mapping).
  Strip: one field, `CompareText.difference`, plus pane 1's zoom.
- Leaving compare, a pane 2 error, or D again drops `session.difference`. If M9's player is on main, pane 1's
  playback pauses while the difference shows and resumes after.

- [ ] **Step 1: Implement**; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh` (menu title in all 30 languages); `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: difference view for compared images`

---

### Task 7: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Samples: the corpus (`swift run -c release featherview-bench
corpus /tmp/fv`), a 4032 × 3024 JPEG and its batch copy at 1000 px, a portrait and a landscape photo, an
EXIF-rotated JPEG, two transparent PNGs, an HDR HEIC, a 10,000-file folder (as in milestone 1's Step 8),
a file in another folder.

- [ ] **Step 1: Check by hand** (release build), light and dark, then Arabic (right-to-left: pane 1 on the
  right, swipes and arrows mirrored as today): ⌥⌘O, the panel's message and start folder; both panes fit
  under their strips; zoom keys, 0, 1, pinch on either pane, scroll and drag on either pane — the same
  detail stays under the same place, also for the resized copy and the rotated file; fling each pane, no
  drift or jitter; in step off and on again; → / ← / held → through the 10,000 folder with pane 2 zoomed
  (pane 2 never blanks); past the end into the folder chooser; X with a second image from another folder
  (the window lists that folder, stays in compare); D on the resized pair, the PNGs, the HDR file, then a
  step and an X with D on; Esc (and in full screen Esc twice), Stop Comparing, the close button, ⌘O and a
  drop leave compare; pane 2's file trashed in Finder → "Can't open", X and D disabled; Trash the last
  image of pane 1's folder; Hide Status Bar and "Hide toolbar and status bar while viewing" in compare.
  If M13's grid is on main and Task 4 Step 4 didn't run, wire it now (Task 4 Step 4) and check two
  selected thumbnails start compare.
- [ ] **Step 2: Measure** with `sudo -n /usr/bin/log show` and Instruments' Points of Interest (5 runs,
  medians): `CompareShow` for a 12 MP JPEG; `Navigate` p50 / p95 stepping pane 1 prefetched and not;
  `Difference` for 12 MP pairs; memory after holding → through 200 images with pane 2 zoomed past fit
  and D on (Decision 11's bound); cold launch unchanged. Fix any miss before going on.
- [ ] **Step 3: Docs:** `docs/spec.md` gets a "Compare" section under "Viewer" with Decisions 1–12 in spec
  wording, X / D / Esc-in-compare in "Keys" (noted as compare-only), ⌥⌘O in "Menu commands", the compare
  budgets in `AGENTS.md`'s table; `docs/parity.md` "Compare images" rows → Featherview column as built,
  status `v2`; roadmap row `| 15 | Compare images (v2) | docs/superpowers/plans/2026-10-22-milestone-15-compare.md | done |`;
  README features line.
- [ ] **Step 4: Commit** `docs: compare images done after manual QA`
