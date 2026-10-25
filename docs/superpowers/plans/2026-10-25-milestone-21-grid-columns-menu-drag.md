# Milestone 21: Grid columns, context menu, drag out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in the main session (no plan-wave: the tasks are small and build on each other). Steps use checkbox (`- [ ]`) syntax for tracking. Task 5 needs the screen and waits for the maintainer's go.

**Goal:** The thumbnail grid's cells fill the window in whole columns (as in Photos), a right-click
menu acts on the selection, and selected cells drag out as files.

**Architecture:** The column arithmetic, the pinch accumulator and the two new selection rules are
pure functions in FeatherviewCore (`GridRules.swift`); `ViewerAvailability` lets ⌘C and Show in
Finder act on the grid's selection. The app's `ThumbnailGrid` coordinator applies the column count
to its flow layout, and `GridCollectionView` gets `magnify(with:)`, `menu(for:)` and a drag source.
The menu's file actions reuse the grid's `GridKey` path, so they behave exactly like their keys.

**Tech Stack:** Swift 6, AppKit (`NSCollectionViewFlowLayout`, `NSMenu`, `NSDraggingSource`,
`NSPasteboard`), Swift Testing.

**Spec:** `docs/spec.md` section "Thumbnail grid" (bullets "Size", "On the selection", "Right-click",
"Dragging", and the list of keys that do nothing in the grid).

## Global Constraints

- Swift 6 strict concurrency; no file reads on the main thread.
- Budgets unchanged (AGENTS.md): T to the grid on screen < 100 ms for 10,000 files (`GridShow`),
  first screen complete < 400 ms (`GridFill`), < 8 ms main-thread work per scrolled frame.
- User-facing text translatable, all 30 languages in `Resources/Localizable.xcstrings`, added by hand
  in the file's existing format. Reuse existing keys ("Copy", "Show in Finder", "Move to Folder…",
  "Copy to Folder…", "Move to Trash"); only "Show Image" and "Batch Convert…" are new.
- Never hard-code colours, radii or durations outside `Theme.swift`; the gap is `Theme.gridGap`, the
  side margin `CanvasInsets.side`.
- Never lose user data: the drag offers `.copy` only.
- TDD for FeatherviewCore: failing test first.
- Layout leading/trailing; comments describe the code as it is.

## Review Focus

1. A window narrower than two 64 pt cells: one column as wide as the room, never zero columns or a
   negative size — Task 1, `columnsInANarrowWindow`.
2. + at the largest size or − at the smallest: nothing changes (no re-layout, no setting written) —
   Task 1, `steppedStopsAtTheRange`; Task 2 calls nothing on nil.
3. The grid before it has a width (first `update` while entering): the target lays out as today and
   the scroll to the current cell still lands in the middle — Task 1, `columnsWithoutWidth`; Task 2
   checks entering in the 10,000 folder.
4. Right-click on an unselected cell while several are selected: only that cell is acted on (Move to
   Trash must not trash the old selection) — Task 1, `contextClickOutsideSelectionReplacesIt`.
5. A drag dropped on the Dock's Trash or on the same disk in Finder: nothing moves or disappears —
   Task 4 (`.copy` mask; checked on screen in Task 5).

---

### Task 1: Core rules

**Files:**
- Modify: `Sources/FeatherviewCore/Viewer/GridRules.swift` (`ThumbnailSize`, `GridSelection`)
- Modify: `Sources/FeatherviewCore/Viewer/ViewerAvailability.swift` (`canCopy`, `canShowInFinder`)
- Test: `Tests/FeatherviewCoreTests/Viewer/GridRulesTests.swift`, `Tests/FeatherviewCoreTests/Viewer/ViewerAvailabilityTests.swift`

**Interfaces:**
- Produces:
  - `ThumbnailSize.Columns: Equatable, Sendable { let count: Int; let cell: Double }` (public memberwise init)
  - `ThumbnailSize.columns(width: Double, target: Double, gap: Double) -> Columns`; `width` is the room
    between the side margins.
  - `ThumbnailSize.stepped(width: Double, target: Double, gap: Double, larger: Bool) -> Double?`, the
    new target, or nil when no column count is left in `range`.
  - `ThumbnailSize.pinchStep = 0.15`
  - `struct PinchSteps: Sendable { init(); mutating func add(_ magnification: Double) -> Int; mutating func end() }`
    (positive steps = larger)
  - `GridSelection.contextClick(_ index: Int, selection: Set<Int>) -> Set<Int>`
  - `GridSelection.defersClick(_ index: Int, selection: Set<Int>, shift: Bool, command: Bool) -> Bool`

- [ ] **Step 1: Write the failing tests** (in `GridRulesTests`)

```swift
@Test func columnsFillTheWidth() {
    #expect(ThumbnailSize.columns(width: 1000, target: 128, gap: 12) == .init(count: 7, cell: 132))
    #expect(ThumbnailSize.columns(width: 1000, target: 256, gap: 12) == .init(count: 4, cell: 241))
    #expect(ThumbnailSize.columns(width: 300, target: 256, gap: 12) == .init(count: 2, cell: 144))  // 1 column: 300 > 256
}
@Test func columnsInANarrowWindow() {
    #expect(ThumbnailSize.columns(width: 50, target: 128, gap: 12) == .init(count: 1, cell: 50))
}
@Test func columnsWithoutWidth() {
    #expect(ThumbnailSize.columns(width: 0, target: 128, gap: 12) == .init(count: 1, cell: 128))
}
@Test func steppedTakesOneColumn() {
    #expect(ThumbnailSize.stepped(width: 1000, target: 128, gap: 12, larger: true) == 156)   // 6 columns
    #expect(ThumbnailSize.stepped(width: 1000, target: 128, gap: 12, larger: false) == 114)  // 8 columns
}
@Test func steppedStopsAtTheRange() {
    #expect(ThumbnailSize.stepped(width: 1000, target: 256, gap: 12, larger: true) == nil)   // 3 columns: 325
    #expect(ThumbnailSize.stepped(width: 1000, target: 64, gap: 12, larger: false) == nil)   // 14 columns: 60
}
@Test func pinchStepsKeepTheRemainder() {
    var pinch = PinchSteps()
    #expect(pinch.add(0.1) == 0)
    #expect(pinch.add(0.1) == 1)
    #expect(pinch.add(-0.4) == -2)
    pinch.end()
    #expect(pinch.add(0.1) == 0)
}
@Test func contextClickInsideSelectionKeepsIt() {
    #expect(GridSelection.contextClick(2, selection: [1, 2, 5]) == [1, 2, 5])
}
@Test func contextClickOutsideSelectionReplacesIt() {
    #expect(GridSelection.contextClick(3, selection: [1, 2, 5]) == [3])
}
@Test func plainClickInsideSeveralWaitsForMouseUp() {
    #expect(GridSelection.defersClick(2, selection: [1, 2], shift: false, command: false))
    #expect(!GridSelection.defersClick(2, selection: [2], shift: false, command: false))
    #expect(!GridSelection.defersClick(3, selection: [1, 2], shift: false, command: false))
    #expect(!GridSelection.defersClick(2, selection: [1, 2], shift: true, command: false))
    #expect(!GridSelection.defersClick(2, selection: [1, 2], shift: false, command: true))
}
```

In `ViewerAvailabilityTests.gridActsOnItsSelection`, replace `!a.canShowInFinder && !a.canCopy` with
`a.canShowInFinder == (selected > 0)` and `a.canCopy == (selected > 0)`.

- [ ] **Step 2: Run them, expect failures**

Run: `swift test --filter "GridRulesTests|ViewerAvailabilityTests"`
Expected: build errors for the missing names, then the availability expectations fail.

- [ ] **Step 3: Implement**

`columns`: width ≤ 0 → `Columns(count: 1, cell: target)`. Else
`cell(n) = ((width - Double(n - 1) * gap) / Double(n)).rounded(.down)`; start at
`n = max(1, Int(((width + gap) / (target + gap)).rounded()))`; while `n > 1 && cell(n) < 64` take one
off; while `cell(n) > 256` add one. `stepped`: `n = columns(…target…).count ∓ 1` (larger = one fewer);
nil if `n < 1` or `cell(n)` is outside `range`, else `cell(n)`. `PinchSteps.add`: add to the running
sum, `steps = Int(sum / pinchStep)` (towards zero), subtract `Double(steps) * pinchStep`, return
`steps`; `end()` zeroes the sum. Availability: `canCopy = !s.isGrid || s.gridSelectionCount > 0`;
`canShowInFinder = s.isGrid ? s.gridSelectionCount > 0 : s.hasCurrent`.

- [ ] **Step 4: Run them, expect PASS**, then `swift test`. The old `stepped(_:larger:)` and its
  test stay until Task 2 removes them with their last caller.

- [ ] **Step 5: Commit** `feat: grid column, pinch and right-click rules in Core`

### Task 2: Columns fill the window

**Files:**
- Modify: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (`Coordinator.update`, `laidOut`, `GridCollectionView`)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`stepThumbnails`, new `gridWidth`)
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (pass the pinch on)

**Interfaces:**
- Consumes: `ThumbnailSize.columns`, `ThumbnailSize.stepped(width:target:gap:larger:)`, `PinchSteps`.
- Produces: `ViewerModel.gridWidth: Double` (`@ObservationIgnored`, the room between the side margins,
  written by the coordinator); `GridCollectionView.onPinch: (Int) -> Void`.

- [ ] **Step 1:** In the coordinator, keep the slider's value as `target`; compute
  `ThumbnailSize.columns(width: scroll.contentView.bounds.width - 2 * CanvasInsets.side, target:, gap: Theme.gridGap)`
  in `update` and in `laidOut` (the width changes there); set `layout.itemSize` and `cellSize` from
  `.cell` only when it changed (setting it inside `layout()` re-enters it), keep the refocus on a new
  decode side, and write `model.gridWidth`.
- [ ] **Step 2:** `stepThumbnails(larger:)`: `guard let size = ThumbnailSize.stepped(width: gridWidth, target: AppSettings.thumbnailSize.value(), gap: Theme.gridGap, larger: larger) else { return }`, then set it. Remove `stepped(_:larger:)` and its test.
- [ ] **Step 3:** `GridCollectionView.magnify(with:)`: feed `event.magnification` to a `PinchSteps`,
  call `onPinch(steps)` when non-zero, `end()` on `.ended` / `.cancelled`. The coordinator wires
  `onPinch` to `model.stepThumbnails(larger: steps > 0)` once per step.
- [ ] **Step 4:** `swift build && swift test`, then `scripts/bundle.sh debug` builds.
- [ ] **Step 5: Commit** `feat: thumbnail grid columns always fill the window, + / − and pinch step one column`

### Task 3: Right-click menu, ⌘C and Show in Finder on the selection

**Files:**
- Modify: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (`GridCollectionView.menu(for:)`, coordinator)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`copyImage`, `showInFinder` in the grid)
- Modify: `Resources/Localizable.xcstrings` ("Show Image", "Batch Convert…", 30 languages)

**Interfaces:**
- Consumes: `GridSelection.contextClick`, the grid's `GridKey` path (`.view`, `.move`, `.copy`,
  `.batch`, `.trash` through `onKey`), `ViewerAvailability.canCopy` / `canShowInFinder`.
- Produces: `ViewerModel.copyGridSelection()`; `showInFinder()` selects `gridSelection` in the grid.

- [ ] **Step 1:** `menu(for event:)`: no cell under the pointer → nil. Else the coordinator applies
  `contextClick` (selection, anchor and focus to that cell when it replaced the selection, via
  `syncSelection(focus:)`) and returns an `NSMenu` with the spec's items and three separators; items
  target the coordinator (`@objc` methods). "Show Image" → `onKey(.view)`; "Move to Folder…",
  "Copy to Folder…", "Batch Convert…", "Move to Trash" → `onKey(.move / .copy / .batch / .trash)`;
  "Copy" → `model.copyGridSelection()`; "Show in Finder" → `model.showInFinder()`. Titles through
  `String(localized:)`.
- [ ] **Step 2:** `copyGridSelection()`: clear the general pasteboard and `writeObjects` the selected
  URLs as `NSURL`s. `copyImage()` calls it when `isGrid`. `showInFinder()`: in the grid,
  `activateFileViewerSelecting(gridSelection)`.
- [ ] **Step 3:** Add the two new keys to the catalog in all 30 languages (match each language's
  existing "Show Image  (T)" and "Batch Convert…  (B)" wording, without the key part).
- [ ] **Step 4:** `swift build && swift test`; `scripts/bundle.sh debug`.
- [ ] **Step 5: Commit** `feat: right-click menu in the thumbnail grid; ⌘C and Show in Finder act on its selection`

### Task 4: Drag selected cells out as files

**Files:**
- Modify: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (`GridCollectionView` mouse handling, `NSDraggingSource`)

**Interfaces:**
- Consumes: `GridSelection.defersClick`, `GridSelection.click`, the cells' shown pictures.

- [ ] **Step 1:** `mouseDown`: on a cell, when `defersClick` is true remember the index and click
  nothing yet; otherwise click as today. Remember the down point and the cell.
- [ ] **Step 2:** `mouseDragged`: past AppKit's drag distance (3 pt) and on a cell that is selected
  after the click, `beginDraggingSession` with one `NSDraggingItem(pasteboardWriter: url as NSURL)`
  per selected URL in list order; each item's frame is its cell's picture frame when the cell is
  visible, else the dragged cell's; contents its shown picture (the `photo` placeholder look when it
  has none). Drop the deferred click.
- [ ] **Step 3:** `mouseUp` without a drag: run the deferred click (`onClick(index, [])`).
- [ ] **Step 4:** `draggingSession(_:sourceOperationMaskFor:)`: `.copy` outside the app, `[]` inside.
- [ ] **Step 5:** `swift build && swift test`; `scripts/bundle.sh debug`.
- [ ] **Step 6: Commit** `feat: drag thumbnails out of the grid as files`

### Task 5: Screen check (waits for the maintainer's go)

- [ ] Columns: resize the window slowly, cells always fill the row; slider, + / −, pinch step one
  column; largest / smallest stop; narrow window shows one column; full screen; two screens'
  backing scales.
- [ ] Menu: right-click inside and outside a selection of three, each item; Control-click; between
  cells nothing; right-to-left language layout.
- [ ] Drag: three cells to Finder on the same disk (copied, originals stay), to Mail, to the Dock's
  Trash (nothing), onto the own window (nothing); plain click inside a selection still selects one.
- [ ] ⌘C then ⌘V in Finder pastes the files; File › Show in Finder selects them.
- [ ] Budgets: `GridShow` 10,000 files < 100 ms, `GridFill` < 400 ms, scrolling < 8 ms per frame
  (Instruments), as in AGENTS.md.
- [ ] Mark row 21 done in `docs/roadmap.md`, move the three items in `ROADMAP.md` to what the next
  release has, commit `docs: milestone 21 done after the screen check`.
