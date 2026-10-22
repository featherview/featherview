# Milestone 18: Quick wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in the main session (no plan-wave: the tasks are small). Steps use checkbox (`- [ ]`) syntax for tracking. Task 6 needs the screen and waits for the maintainer's go.

**Goal:** Four small gaps to the reference viewer, built on what milestones 11 and 13 left in place:
Refresh (F5), a random image key, where a desktop picture goes, and file details in the thumbnail
grid's tooltips.

**Architecture:** Refresh is Follow New Files' rescan (M11 Task 9) without its jump to the newest file.
The random pick and the tooltip text are small pure functions in FeatherviewCore (`ImageList`,
`GridText`); the desktop picture placement is a Core enum mapped to `NSWorkspace` options. The app adds
keys, menu items and one hover read per grid cell.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSWorkspace.setDesktopImageURL`, `NSView` tool tips),
Swift Testing.

**Spec:** `docs/spec.md` (Task 1 adds the four behaviours); `docs/parity.md` rows "Folder list" (F5),
"Random", "Desktop picture", "Hover".

**Starts after:** milestone 11 Task 9 (`folderChanged()`), Task 5 (`relist`), Task 6
(`setDesktopPicture()`) and milestone 13 Task 5 are merged.

## Global Constraints

- Swift 6 strict concurrency; no file reads on the main thread (AGENTS.md budgets).
- User-facing text translatable (`String(localized:)` or SwiftUI literals), all 30 languages in
  `Resources/Localizable.xcstrings`, added by hand in the file's existing format (not by re-running
  `scripts/strings.sh` on the whole catalog).
- Matching single-key shortcuts is allowed; menu and UI text are our own, Mac wording.
- Never hard-code colours, radii or durations outside `Theme.swift`.
- TDD for FeatherviewCore: failing test first. Test images from `Fixtures`.

## Review Focus

1. Refresh while the current file was deleted outside the app: the image at the same position shows
   (as after Move to Trash), never a blank window or a crash — Task 2, `refreshKeepsPositionWhenCurrentIsGone`.
2. Random on a one-image folder: nothing happens (no flicker, no re-decode) — Task 3, `randomNeedsTwoImages`.
3. Random never picks the image already shown — Task 3, `randomNeverPicksCurrent`.
4. Tooltip for a file that can't be read: "Can't open <name>" stays, no details line — Task 5,
   `tooltipForFailedFile`.
5. Desktop picture on several screens: every screen gets the same placement — Task 4 (screen check in
   Task 6).

---

### Task 1: Spec and parity

**Files:**
- Modify: `docs/spec.md` (section "Viewer", keys table and View / Image menus; section "Thumbnails")
- Modify: `docs/parity.md` rows "Folder list" (F5), "Random", "Desktop picture", "Hover"

- [ ] **Step 1: Add to the spec, in our words:**
  - Refresh: F5 and ⌘R, View › "Refresh  (F5)" after Sort By. Rescans the folder now (also with Follow New
    Files off): new images join the list in sort order, vanished ones leave it, the current image stays on
    screen; if it is gone, the image at its position shows, as after Move to Trash. Disabled without a
    folder.
  - Random image: the key observed in Task 3 Step 1, Image › "Random Image" after Previous. Shows a random
    other image of the list; nothing with fewer than two images; off during a slideshow (its own order) and
    in the grid.
  - Desktop picture: Image › "Set as Desktop Picture" becomes a submenu: Fill Screen (default, the current
    behaviour), Fit to Screen, Stretch to Fill Screen, Center. Every screen gets the picture. Fit and Center
    leave the rest of the screen black.
  - Thumbnails: hovering a cell shows its name, then pixel size, file size, position ("3 / 120") and date,
    read when the pointer arrives (never while scrolling); a file that can't be opened keeps "Can't open
    <name>".
- [ ] **Step 2: Set the four parity rows' status to `v2` and their Featherview column to the above.**
- [ ] **Step 3: Commit:** `git commit -m "docs: spec for Refresh, random image, desktop picture placement and grid tooltips"`

### Task 2: Refresh (F5)

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel+FollowNewFiles.swift` (or wherever M11 Task 9 put
  `folderChanged()`)
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (`handle`: F5; View menu item)
- Test: `Tests/FeatherviewCoreTests/Viewer/ImageListTests.swift`

**Interfaces:**
- Consumes: M11 Task 9 `folderChanged()` internals; `relist(_:)`; `ImageList.reorder(_:)`.
- Produces: `func refreshFolder()` on `ViewerModel`; `availability.canRefresh: Bool` = `folder != nil` (in the
  grid too: the grid shows the refreshed list).

- [ ] **Step 1: Write the failing test** `refreshKeepsPositionWhenCurrentIsGone` in `ImageListTests`:
  a list `[a, b, c]` on `b`; `reorder([a, c])` → `current == c`; `reorder([a, c, d])` on `c` → `current == c`.
  (If `reorder` already behaves so, the test documents it and passes at once: then go to Step 3.)
- [ ] **Step 2: Run** `swift test --filter ImageListTests` → FAIL only if `reorder` loses the position.
- [ ] **Step 3: Split `folderChanged()`** into `private func rescan() async -> (added: [URL], newest: URL?)?`
  (scan, `Arrivals.diff`, cache drops, `readSortValues(for: added)`, `relist(scanned)`; nil when superseded)
  and the follow part (settle, select newest, `show()`). `refreshFolder()` queues behind `rotateTask` and
  `openTask` like `folderChanged()`, runs `rescan()`, then `show()` only if the current URL changed.
  While an unsaved clipboard image is up it marks `pendingRescan`, as `folderChanged()` does.
- [ ] **Step 4: Keys and menu:** F5 (`NSF5FunctionKey`) in `handle` next to F7 / F8, and in `GridKey`'s
  pass-on list; View › "Refresh  (F5)" with `.keyboardShortcut("r")`, disabled by `!canRefresh`.
  "Refresh  (F5)" in all 29 languages.
- [ ] **Step 5: Run** `swift build && swift test` → all pass.
- [ ] **Step 6: Commit:** `git commit -m "feat: Refresh (F5, ⌘R) rescans the folder and keeps the image shown"`

### Task 3: Random image

**Files:**
- Modify: `Sources/FeatherviewCore/Viewer/ImageList.swift`
- Modify: `Sources/FeatherviewCore/Viewer/ViewerKey.swift` (new case `randomImage`)
- Modify: `Sources/FeatherviewCore/Viewer/GridRules.swift` (`GridKey.action`: `randomImage` → nil)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift`, `ViewerView.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/ImageListTests.swift`, `ViewerKeyTests.swift`

**Interfaces:**
- Produces: `ImageList.selectRandom<G: RandomNumberGenerator>(using generator: inout G) -> Bool`;
  `ViewerKey.randomImage`; `ViewerModel.randomImage()`.

- [ ] **Step 1: Observe the key** with the `observe-reference` skill: which key shows a random file, and
  whether it repeats the shown one. Record it in the parity row "Random". If the key is taken in
  `ViewerKey` (R, L, I, F, 0–3, H, V, +, −, O, B, M, P, S, A, G, T, X, D, W), use ⇧ plus that letter if
  free, else no single key (menu item only), and say so in the spec line from Task 1.
- [ ] **Step 2: Write the failing tests** in `ImageListTests`:
  - `randomNeverPicksCurrent`: list of 5 on index 2, a seeded generator, 200 calls → `current` never equals
    the URL before each call, and every other URL is picked at least once.
  - `randomNeedsTwoImages`: list of 1 → `selectRandom` returns false, `current` unchanged; empty list → false.
  - `randomReleasesHeld`: a list holding a removed file (`remove(_:hold: true)`) → after `selectRandom`,
    `isHolding == false`.
  And in `ViewerKeyTests`: `randomKey` — the observed character maps to `.randomImage`.
- [ ] **Step 3: Run** `swift test --filter "ImageListTests|ViewerKeyTests"` → FAIL (no `selectRandom`).
- [ ] **Step 4: Implement `selectRandom(using:)`**: pick an index in `0..<count-1` and skip over the current
  index, release `held`; a test-only seeded generator (`SplitMix64` in the test file) drives it.
- [ ] **Step 5: Run** the filter again → PASS.
- [ ] **Step 6: App:** `ViewerModel.randomImage()` — guard no slideshow, not the grid, not holding an unsaved
  clipboard image; `list.selectRandom(using: &generator)` with `SystemRandomNumberGenerator`, then `show()`.
  Image › "Random Image  (<key>)" after Previous; `perform(.randomImage)`. Translations in all 29 languages.
- [ ] **Step 7: Run** `swift build && swift test` → all pass.
- [ ] **Step 8: Commit:** `git commit -m "feat: Random Image shows another image of the folder at random"`

### Task 4: Desktop picture placement

**Files:**
- Create: `Sources/FeatherviewCore/App/DesktopPlacement.swift`
- Modify: `Sources/Featherview/Viewer/ViewerModel+Recents.swift` (`setDesktopPicture`)
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (Image menu and context menu)
- Test: `Tests/FeatherviewCoreTests/App/DesktopPlacementTests.swift`

**Interfaces:**
- Produces: `public enum DesktopPlacement: CaseIterable, Sendable { case fill, fit, stretch, center }` with
  `public var scalingRawValue: UInt` (`NSImageScaling`'s raw value: Core doesn't import AppKit) and
  `public var allowsClipping: Bool`;
  `ViewerModel.setDesktopPicture(_ placement: DesktopPlacement)`.

- [ ] **Step 1: Write the failing test** `placementsMapToWorkspaceOptions`:
  fill → (3, true); fit → (3, false); stretch → (1, false); center → (2, false) — `NSImageScaling`'s raw
  values for proportionallyUpOrDown, axesIndependently and none; `allCases.count == 4`.
- [ ] **Step 2: Run** `swift test --filter DesktopPlacementTests` → FAIL (type missing).
- [ ] **Step 3: Implement `DesktopPlacement`** in Core, Foundation only.
- [ ] **Step 4: Run** the filter → PASS.
- [ ] **Step 5: App:** `setDesktopPicture(_:)` passes `.imageScaling` (`placement.scalingRawValue`), `.allowClipping` and
  `.fillColor: NSColor.black` for every screen; the Image menu item becomes a `Menu("Set as Desktop Picture")`
  with "Fill Screen", "Fit to Screen", "Stretch to Fill Screen", "Center" (each disabled by
  `!canSetDesktop`); the context menu gets the same submenu. 5 strings in all 29 languages.
- [ ] **Step 6: Run** `swift build && swift test` → all pass.
- [ ] **Step 7: Commit:** `git commit -m "feat: Set as Desktop Picture fills, fits, stretches or centres"`

### Task 5: File details in grid tooltips

**Files:**
- Modify: `Sources/FeatherviewCore/Viewer/GridText.swift`
- Modify: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (`ThumbnailCell`, `updateTooltip()`)
- Test: `Tests/FeatherviewCoreTests/Viewer/GridTextTests.swift`

**Interfaces:**
- Consumes: `FileInfo.read(url:page:)`, `StatusLine.make(...)`.
- Produces: `public static func tooltip(name: String, info: FileInfo?, index: Int, count: Int, failed: Bool) -> String`
  in `GridText`.

- [ ] **Step 1: Write the failing tests** in `GridTextTests`:
  - `tooltipWithDetails`: name "a.jpg", info 4032 × 3024, 2,400,000 bytes, a fixed date, index 2, count 120
    → first line "a.jpg", second line the `StatusLine.make(pixelSize:zoomPercent: nil, fileBytes:index:count:
    page: 0, pageCount: 1, modified:)` fields joined by "  ·  " (so it contains "3 / 120" and "4032 × 3024").
  - `tooltipWithoutInfo`: info nil → just the name.
  - `tooltipForFailedFile`: failed true → "Can't open a.jpg" whatever the info.
- [ ] **Step 2: Run** `swift test --filter GridTextTests` → FAIL.
- [ ] **Step 3: Implement `GridText.tooltip`.**
- [ ] **Step 4: Run** the filter → PASS.
- [ ] **Step 5: App:** `ThumbnailCell` adds a tracking area (`.mouseEnteredAndExited`, `.activeInKeyWindow`,
  `.inVisibleRect`); `mouseEntered` starts `Task.detached { FileInfo.read(url:page: 0) }` once per URL,
  cancelled in `prepareForReuse` and `mouseExited`; on completion, if the cell still shows that URL,
  `toolTip = GridText.tooltip(...)` with the cell's index and the grid's count. Before the read finishes the
  tooltip is the name, as now. A grid model cache isn't needed: AppKit shows the tip after ~1 s, the read
  takes a few ms.
- [ ] **Step 6: Run** `swift build && swift test` → all pass.
- [ ] **Step 7: Commit:** `git commit -m "feat: grid tooltips show each file's size, position and date"`

### Task 6 (main session, maintainer's go): screen check and docs

- [ ] **Step 1:** Build (`scripts/bundle.sh debug`), sample folder with 30 images. Check: F5 after adding and
  deleting files in Finder (image stays / position kept); ⌘R; the random key 20 times (never the same image
  twice in a row, never in a slideshow); each desktop placement on every screen; grid tooltip after a 1 s
  hover, a failed file's tooltip, fast scrolling shows no stutter (`log stream` grid fill line unchanged).
- [ ] **Step 2:** Roadmap row 18 → done; README "Organising" gains Refresh, Random Image and the placements
  (on the release README branch if it isn't merged yet).
- [ ] **Step 3: Commit:** `git commit -m "docs: milestone 18 done"`
