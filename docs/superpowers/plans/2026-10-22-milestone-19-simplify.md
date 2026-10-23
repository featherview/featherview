# Milestone 19: Simplify Implementation Plan

> **For agentic workers:** Run with the `plan-wave-lite` workflow, tasks in order (they share `ViewerModel.swift`).
> Tasks 8 and 9 run in the main session. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Move the decisions the app target makes into FeatherviewCore, where they get unit tests, and remove the
friction that cost the most review rounds in milestones 11–17: the string catalog's format and duplicated code.
No behaviour changes.

**Why:** The app target has no unit tests (AGENTS.md: "if logic can be tested without a window, it belongs in
FeatherviewCore"). `ViewerModel.swift` grew to ~1,700 lines, and the defects reviewers found in milestones 11–16
were mostly decisions living there: which commands an unsaved pasted picture allows, a slideshow's skip-or-show
rule for a failed decode, when Open Recent re-reads the system's list, which actions each mode enables. Each
moves into a small Core value type or pure function with tests, like `Slideshow`, `GridRules` and `ImageList`
already are; `ViewerModel` keeps only the wiring (state, decode tasks, AppKit).

**Starts after:** every wave of milestones 11–17 is merged (`ViewerModel` stops moving); before milestone 18.

**Tech Stack:** Swift 6, Swift Testing, `xcrun xcstringstool`.

## Global Constraints

- No behaviour change: every existing test passes unchanged; a moved rule keeps its exact conditions. Where the
  move shows a rule was inconsistent, write it down for the maintainer instead of changing it.
- FeatherviewCore imports no SwiftUI or AppKit.
- TDD: the Core type's tests first, written from the current app code's conditions, then the move.
- Comments describe code as it is (no "moved from", no history).

## Review Focus

1. A moved rule silently changes behaviour in a mode combination the old code handled by ordering (grid +
   unsaved, compare + slideshow): each Core type gets a test per mode combination it decides.
2. The catalog reformat changes content, not only layout: Task 1 compares the parsed JSON before and after.
3. The merge script loses a key or a translation when both sides add the same key with different content: it
   must stop and name the key, never pick one.
4. A Core type captures state the app mutates elsewhere (a stale snapshot): each pure function takes a value
   snapshot built at the call site, never a reference.
5. Duplicates removed in Task 7 differed slightly (a modifier missed in one copy): unify to the superset and
   say which copy changed.

---

### Task 1: String catalog in the tool's own format, and a merge script

**Files:**
- Modify: `Resources/Localizable.xcstrings` (format only)
- Create: `scripts/merge-strings.py`
- Modify: `AGENTS.md` (Commands: `scripts/strings.sh` and `scripts/merge-strings.py`)

- [x] **Step 1:** Save the parsed catalog (`python3 -c 'import json; json.load(...)'`), run `scripts/strings.sh`,
  and compare: the only allowed differences are layout and new or stale `extractionState` markers. Any key that
  appears untranslated is a real gap: translate it in this task (all 29 languages), as in commit ada06d1.
- [x] **Step 2:** Commit the catalog alone: `chore: string catalog in xcstringstool's own format`.
- [x] **Step 3:** Write `scripts/merge-strings.py`: run during a merge conflict on the catalog, it reads stages
  1/2/3 (`git show :N:Resources/Localizable.xcstrings`), keeps ours, adds keys theirs added or changed, stops
  with exit 1 naming any key both sides changed differently, and writes the file byte-for-byte in the tool's
  format (check: reading the Step 2 file and writing it back gives an identical file — `cmp`).
- [x] **Step 4:** AGENTS.md Commands: "after changing UI text: `scripts/strings.sh`, then translate the new keys"
  (drop any advice to edit the catalog by hand), and "catalog merge conflict: `scripts/merge-strings.py`, then
  `git add Resources/Localizable.xcstrings`". Update the `plan-wave-lite` workflow's STRINGS text and merge
  prompt to match.
- [x] **Step 5: Commit:** `chore: merge-strings script; strings.sh is the way to add UI text`

### Task 2: Which actions each mode allows (`ViewerAvailability`)

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/ViewerAvailability.swift`
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`Availability`, `updateAvailability()`, `canShowInfo`,
  `canAdjustDate`, and any other computed "can…" property)
- Test: `Tests/FeatherviewCoreTests/Viewer/ViewerAvailabilityTests.swift`

**Interfaces:**
- Produces: `public struct ViewerState: Sendable` (a snapshot: `hasCurrent`, `isHolding`, `isOpening`, `isEmpty`,
  `index`, `count`, `pageCount`, `frameCount`, `isGrid`, `gridSelectionCount`, `isComparing`, `compareFailed`,
  `isSlideshow`, `hasUnsaved`, `hasFolder`, `pastEnd: PastEndBehavior`) and
  `public struct ViewerAvailability: Equatable, Sendable` with the fields `Availability` has today plus
  `canShowInfo` and `canAdjustDate`, built by `public init(_ state: ViewerState)`.
  `ViewerModel.availability` becomes a `ViewerAvailability`; `updateAvailability()` builds the snapshot.

- [x] **Step 1:** Tests, one per mode and the combinations: plain viewer; holding a removed file; opening; empty
  list; grid (with 0, 1, 2 selected); compare (and its failed second file); slideshow; unsaved pasted picture
  (Next/Previous/Home/End enabled so they can ask, file actions, T, W and Compare disabled); multi-page; animation.
  Expected values copied from today's `updateAvailability()` and the menu `.disabled` conditions.
- [x] **Step 2–4:** fail, implement, pass. Replace every `.disabled(...)` in `ViewerView.swift`,
  `ViewerToolbar.swift` and `ConvenienceMenus.swift` that recomputes a condition with the matching field.
- [x] **Step 5: Commit:** `refactor: what each viewer mode allows is decided and tested in Core`

### Task 3: A slideshow's failed decode (`Slideshow.decodeFailed`)

**Files:** `Sources/FeatherviewCore/Viewer/Slideshow.swift`, `Sources/Featherview/Viewer/ViewerModel.swift`
(the catch branch of `show()`), `Tests/FeatherviewCoreTests/Viewer/SlideshowTests.swift`

**Interfaces:**
- Produces: `public enum FailedDecode: Equatable { case skip(to: URL?), showError }` and
  `public mutating func decodeFailed(_ url: URL) -> FailedDecode` on `Slideshow`: `.skip` (through `failed(_:)`)
  while `current` hasn't been shown, `.showError` once it has (`shownCurrent`), or when `url != current`.

- [x] **Step 1:** Tests: first decode of the current file fails → skip; after `shown` → showError; a later page or
  zoom failure of a shown file → showError; every file failing → `.skip(to: nil)`; paused → showError for a shown file.
- [x] **Step 2–4:** fail, implement, pass; the catch branch calls it; `shownCurrent` goes back to `private(set)`
  use only inside `Slideshow`.
- [x] **Step 5: Commit:** `refactor: a slideshow's skip-or-show rule lives in Slideshow`

### Task 4: When Open Recent reads the system's list (`RecentCheck`)

**Files:** `Sources/FeatherviewCore/Viewer/RecentList.swift`, `Sources/Featherview/Viewer/ViewerModel+Recents.swift`,
`Tests/FeatherviewCoreTests/Viewer/RecentListTests.swift`

**Interfaces:**
- Produces: `public struct RecentCheck: Sendable` with `public mutating func request() -> Source?`
  (`.system` for the first check, `.ownList` after; nil while one runs — remembered for one rerun) and
  `public mutating func finished(missing: Bool) -> Source?` (`.system` when an own-list check found an entry
  missing, the remembered rerun's source otherwise, nil when done). `public enum Source { case system, ownList }`.
- [x] **Step 1:** Tests: first request reads the system; later ones the own list; a burst of requests while one
  runs gives exactly one rerun; a missing entry leads to one system read, never two in a row; clear's generation
  is unaffected (it stays in `RecentList`).
- [x] **Step 2–4:** fail, implement, pass; `RecentFiles` keeps the queue and NSDocumentController calls only.
- [x] **Step 5: Commit:** `refactor: when Open Recent reads the system's list is decided in Core`

### Task 5: What an unsaved pasted picture lets through (`UnsavedRules`)

**Files:** `Sources/FeatherviewCore/Viewer/UnsavedRules.swift` (new), `ViewerModel.swift`,
`ViewerModel+Clipboard.swift`, `Tests/FeatherviewCoreTests/Viewer/UnsavedRulesTests.swift`

**Interfaces:**
- Produces: `public enum ViewerCommand` (next, previous, first, last, open, close, newFromClipboard, quit) and
  `public static func asksFirst(_ command: ViewerCommand, hasUnsaved: Bool) -> Bool`; every app entry point that
  leaves the picture calls `leaveUnsaved` exactly when this says so (one guard helper, not a copy per function).
- [x] **Step 1:** Tests: each command with and without an unsaved picture (all leaving commands ask; nothing asks
  without one).
- [x] **Step 2–4:** fail, implement, pass. The per-function `if unsaved != nil { return leaveUnsaved { … } }`
  copies become one `guardUnsaved(_ command:, then:)`.
- [x] **Step 5: Commit:** `refactor: which commands ask before leaving a pasted picture is one tested rule`

### Task 6: Pending rotations and flips (`PendingChanges`)

**Files:** `Sources/FeatherviewCore/Imaging/PendingChanges.swift` (new), `ViewerModel.swift`
(`pendingChanges`, `pendingTransform`, `writtenChanges` and their updates), tests alongside.

**Interfaces:**
- Produces: `public struct PendingChanges: Sendable` with `add(_ change: OrientationChange)`,
  `written(_ change:)`, `failed() -> OrientationChange?` (removes the first not yet written),
  `decodedAgain()` (drops the written ones), `reset()` and `var transform: PictureTransform`.
- [x] **Step 1:** Tests from M12's rules: R then V shows the combined transform; a new decode of the same file drops
  written changes; another file clears all; a failure removes the first unwritten change.
- [x] **Step 2–4:** fail, implement, pass.
- [x] **Step 5: Commit:** `refactor: pending rotations and flips are a tested Core value`

### Task 7: Duplicated code

**Files:** as found; at least `Sources/FeatherviewCore/Viewer/MenuKey.swift` and the two copies of the
modifier-flag mapping (`ThumbnailGrid.swift` `keyDown`, `ViewerView.swift` grid key handling).

- [x] **Step 1:** `MenuKey.Modifiers.init(command:shift:option:control:)` in Core (test: each flag), used by both
  copies (AppKit and SwiftUI flags convert at the call site).
- [x] **Step 2:** Search the app target for other copies (repeated `.disabled` conditions not covered by Task 2,
  repeated error-message building, repeated open-panel setup) and fold each into one function in the file that
  owns it. List each in the commit message.
- [x] **Step 3: Commit:** `refactor: one copy each of the modifier mapping and <list>`

### Task 8: Simplify over the whole project (main session)

The `simplify` skill reviews changed code by default; here it gets the whole project as its scope, because the
duplication and dead code this milestone is after sit between milestones, not inside one diff.

- [x] **Step 1: Invoke** `Skill(simplify, args: "Scope: the whole repository at main, not a diff. Context:
  docs/spec.md (requirements), AGENTS.md (rules: layering — logic that needs no window lives in FeatherviewCore;
  Theme tokens; translatable text; no history in comments), docs/roadmap.md (milestones 1–19), and this plan
  (Tasks 1–7 already moved the viewer's decisions into Core). Cover Sources/FeatherviewCore, Sources/Featherview,
  Sources/FeatherviewThumbnail, Sources/FeatherviewPreview, Sources/FeatherviewBench, Sources/FeatherviewDMG,
  Tests/, scripts/, .github/workflows/ and .claude/workflows/. Not Sources/CJPEGXL, Sources/CJPEGXR (vendored).
  Look for: code that duplicates a Core helper; helpers used once; dead code and unused settings keys; stale
  catalog keys (extractionState stale); `shortcut:` comments whose condition has passed (run ponytail-debt
  first); decisions still made in app files that Tasks 2–6 missed; test fixtures that duplicate Fixtures.
  No behaviour changes.")`.
- [x] **Step 2:** Apply what is clearly dead or duplicated, one commit per area (`refactor:` / `chore:`), each with
  `swift build` and `swift test` green. Anything that would change behaviour or needs a decision goes to a list
  for the maintainer instead.
- [x] **Step 3:** One review agent over the whole milestone's diff against its starting commit (no behaviour
  change, budgets unaffected); fix what it confirms.

### Task 9 (main session): measure, docs

- [x] **Step 1:** Budgets unchanged: `featherview-bench decode` and `browse` against the milestone's start
  (`--baseline`), and `swift test` time.
- [x] **Step 2:** `ViewerModel.swift` line count before and after in the commit message; roadmap row 19 → done.
- [x] **Step 3: Commit:** `docs: milestone 19 done`
