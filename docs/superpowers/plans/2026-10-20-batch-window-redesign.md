# Batch window redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** The batch window gets an obvious first move and follows the user's order (images → format →
size → name): numbered fold-open cards, rare steps added on demand, the preview always visible, a
clear running view and a summary in sentences.

**Architecture:** The batch engine stays. Core changes are small and tested: the three-way mode
becomes a `changeFormat` flag (old settings and presets translate on decode), Rotate & Flip gets a
stored on/off, an empty output folder means "next to the originals" for every batch, and a
keep-format batch re-saves each file in its own format or fails it. The step list (`BatchStep`)
becomes a card model (`BatchCard`) with word summaries, the processing-order line and the done
summary, all in Core. The app's batch views are rebuilt around it; the per-step settings views are
reused inside the cards.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), Swift Testing, the String Catalog (`scripts/strings.sh`).

**Spec:** `docs/superpowers/specs/2026-10-20-batch-window-redesign-design.md` (the design), and
`docs/spec.md` "Batch window" (everything the design doesn't change). Rules: `AGENTS.md`.

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency; no new dependency.
- Colours, radii, durations only from `Sources/Featherview/Design/Theme.swift`; leading/trailing,
  never left/right; Reduce Motion → plain cuts (existing `Theme` motion helpers).
- Every user-facing string translatable; sentences are whole catalog strings with placeholders,
  never concatenated; errors name the file ("Can't save IMG_0412.CR3 in its own format").
- Old settings and presets keep producing the same files (design anti-goal); decoding stays
  tolerant (missing or wrong-typed keys fall back to defaults).
- The window with 10,000 images never stalls on opening a card, adding a step or changing a setting.
- Window minimum stays 960 × 600.
- Clean-room: our own design; nothing from the reference viewer's dialog layout.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments in
  the form `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- An old preset saved in "Convert" mode with a custom rename pattern (the pattern was ignored):
  must still produce original names. Pinned in Task 2 (`oldConvertPresetKeepsNames`).
- Keep format with a mixed list (JPEG, PNG, a camera RAW, a DCX) and Size on: JPEG/PNG re-saved
  in their own formats, RAW and DCX fail by name, the rest of the batch runs. Pinned in Task 2
  (`keepFormatMixedList`).
- Keep format, nothing changes the pixels, output next to the originals: byte-identical copies
  with " 2" names, never touching the originals. Pinned in Task 2 (`keepFormatCopiesBesideOriginals`).
- New Batch after a run with failures and a file that was never started (Stop): converted rows go,
  failed and not-started rows stay. Pinned in Task 3 (`newBatchKeepsFailedAndUnstarted`).
- A preview squeezed by a tall card (Text, Watermark unfolded) at the 960 × 600 minimum: preview
  keeps 160 pt, settings scroll. Checked in Task 6 on screen.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 (main session) | the 10,000-image stall, measured on screen, before any view changes |
| B | 2 | core settings and engine rules |
| C | 3 | core card model and summaries (uses 2) |
| D | 4 | the setup window (uses 3) |
| E | 5 | running and done (uses 3, 4) |
| F | 6 (main session) | strings, 30 translations, spec, screen check |

---

### Task 1: The 10,000-image stall (main session, screen) — measured, fix moved to Task 4

Measured on the current window (release build, 10,000 JPEGs via "Use Viewer's Folder", 20 step
clicks timed from a `CGEvent` click until an Accessibility query answers; harness in the gitignored
`research/batch-timing/`, build and run with its `run.sh`):

- The stall of several seconds came from the accessibility client, not from the window: every AX
  call that walks the image list (System Events' `click at`, or a harness listing all rows) makes
  the table build a row view for each of the 10,000 rows. A harness must never enumerate that list.
- Clicking a step: median 7–10 ms, ~90 ms when the settings view changes, the same with an
  empty list, so not caused by the image count.
- Right after adding 10,000 images: one hitch of ~750 ms. Cause: the images `List` in the
  sidebar style is a source list; each row insert makes `NSOutlineView` check for flat indentation
  (`_shouldHaveFlatIndentation`), which loads every item. With `.listStyle(.plain)` (or `.inset`)
  the hitch is gone (p95 95–104 ms over 3 runs).
- At 960 pt wide with Canvas open, the window's content is wider than the window (the note
  next to "Bottom" pushes it out on both sides); Format and Folder fits.

- [x] **Steps 1–3:** harness, measurement, profile (above).
- [x] **Steps 4–6:** fix and re-measure go into Tasks 4 and 6, which rebuild these views.

---

### Task 2: Settings and engine: change format, keep format, next to the originals

**Files:**
- Modify: `Sources/FeatherviewCore/Batch/BatchSettings.swift`, `BatchNamer.swift`, `BatchConverter.swift`,
  `BatchSteps.swift` (`BatchProgress.canStart` only), `Sources/FeatherviewCore/Batch/GeometrySteps.swift`
  (orientation reads the flag)
- Test: `Tests/FeatherviewCoreTests/Batch/BatchSettingsTests.swift`, `BatchNamerTests.swift`, `BatchConverterTests.swift`

**Interfaces:**
- Produces:
  - `BatchSettings.changeFormat: Bool` (default `true`); `BatchMode` and `BatchSettings.mode` are
    removed (decoding still reads the old `mode` key).
  - `OrientationSettings.isOn: Bool` stored (default `false`); the pipeline applies rotate/flip only
    when it's on.
  - `BatchSettings.copiesUnchanged: Bool` — `!changeFormat && !hasOperations`.
  - `BatchSettings.outputFolder == ""` means next to each original, for every batch.
  - `BatchProgress.canStart(...)`: inputs > 0, not running, no scan, and the folder empty or absolute.

Rules to pin (from the design):

- Decoding, when the stored settings have a `mode` key and no `changeFormat` key:
  `convert` → `changeFormat = true`, `renamePattern = "{name}"`; `rename` → `changeFormat = false`,
  every operation's `isOn = false`; `convertAndRename` → `changeFormat = true`, pattern kept.
  Stored settings without `orientation.isOn` get `isOn = rotate != .none || flipHorizontal || flipVertical`.
- Names: `RenamePattern` always applies (`{name}` = unchanged). Extension: the output format's when
  `changeFormat`, else the input's own.
- Keep format (`!changeFormat`): `copiesUnchanged` → copy the bytes (today's rename path). Otherwise
  each file is encoded in the writable `OutputFormat` matching its own type
  (`FormatRegistry` by the input's UTType; options `FormatSettings.options(for:)`); when there is
  none, or the input has several pages and that format can't hold them, the file fails with
  `String(localized: "Can't save \(name) in its own format")`. The watermark loads whenever
  `watermark.isOn` (no mode check).

- [x] **Step 1: Write the failing tests:**
  - `BatchSettingsTests`: `oldConvertPresetKeepsNames` (JSON `{"mode":"convert","renamePattern":"x-{n}"}`
    → `changeFormat == true`, `renamePattern == "{name}"`); `oldRenamePresetKeepsFormatAndDropsOperations`
    (`{"mode":"rename","resize":{"isOn":true}}` → `changeFormat == false`, `resize.isOn == false`);
    `oldConvertAndRenameKeepsPattern`; `newSettingsIgnoreOldMode` (both keys present → `changeFormat` wins);
    `oldOrientationTurnsOnWhenSet` (`{"orientation":{"rotate":"left"}}` → `orientation.isOn`);
    `roundTripKeepsEverything`.
  - `BatchNamerTests`: `keepFormatKeepsExtension`; `patternAppliesWithoutMode`;
    `emptyFolderIsNextToOriginal` (for a converting batch too).
  - `BatchConverterTests` (Fixtures images in temp dirs): `keepFormatCopiesBesideOriginals`
    (JPEG + PNG, nothing on, folder "" → outputs `a 2.jpg`, `b 2.png`, bytes equal to the inputs,
    inputs untouched); `keepFormatResavesInOwnFormat` (JPEG with resize on → output is a JPEG of the
    new size); `keepFormatMixedList` (JPEG, PNG, a file named `.dcx` with two pages built as in
    `QuickLookSupportTests.multiPageShowsFirstPage`, and a `.cr3` file made by copying a JPEG's bytes
    under that name — ImageIO reads it, nothing writes it; resize on → JPEG and PNG converted, DCX
    and CR3 failed with "Can't save … in its own format", in list order); `canStartWithEmptyFolder`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter "BatchSettingsTests|BatchNamerTests|BatchConverterTests"`
- [x] **Step 3: Implement** the interfaces and rules above. Remove every `mode` use
  (`BatchConverter.swift:45,119-122`, `BatchNamer.swift:55,58`, `BatchSteps.swift:42,72`).
  The app still compiles: replace the toolbar's mode picker in `BatchView.swift` with nothing yet
  and `BatchStepViews.swift:71`'s `.disabled` with `!changeFormat` (Task 4 replaces both views).
- [x] **Step 4: Run the full suite.** `swift test` → all pass (update tests that used `BatchMode`:
  `BatchNamerTests.settings(_:)` takes `changeFormat:` instead).
- [x] **Step 5: Commit** `feat: batch keeps or changes the format per file; old presets load the same batch`

---

### Task 3: Card model, summaries and New Batch in Core

**Files:**
- Modify: `Sources/FeatherviewCore/Batch/BatchSteps.swift` (replace `BatchStep` with `BatchCard`)
- Create: `Sources/FeatherviewCore/Batch/BatchReport.swift`
- Modify: `Sources/FeatherviewCore/Batch/BatchInputList.swift`
- Test: `Tests/FeatherviewCoreTests/Batch/BatchStepsTests.swift`, `BatchReportTests.swift`, `BatchInputListTests.swift`

**Interfaces:**
- Consumes: Task 2's `changeFormat`, `copiesUnchanged`, `OrientationSettings.isOn`, empty folder rule.
- Produces:
  - `public enum BatchCard: String, CaseIterable, Identifiable, Sendable { case format, size, name, crop, orientation, colour, filters, canvas, border, text, watermark }`
    with `static let core: [BatchCard] = [.format, .size, .name]`,
    `static let extras: [BatchCard]` (the eight others, in this order: crop, orientation, colour,
    filters, canvas, border, text, watermark),
    `func isAdded(in: BatchSettings) -> Bool` (core: always true; extras: the step's `isOn`),
    `func setAdded(_ on: Bool, in: inout BatchSettings)`,
    `func summary(in: BatchSettings) -> String`,
    `var number: Int?` (format 2, size 3, name 4, extras nil).
  - `public static func appliedLine(_ s: BatchSettings) -> String?` on `BatchCard`: the steps that
    are on, in processing order (spec "Per-image operations", Size where Resize runs), joined
    `" → "` after "Applied:" as one catalog string with a placeholder; nil when nothing is on.
  - `public enum BatchReport` with
    `static func summary(results: [BatchResult], seconds: Double, bytesIn: Int, bytesOut: Int, folder: String) -> String`
    and `static func failures(_ results: [BatchResult]) -> [String]` (each failed result's log line).
  - `BatchInputList.keep(_ urls: Set<URL>)` — removes every input whose URL isn't in the set, order kept.

Summaries (whole catalog strings, `String(localized:)` with comments): format: the format name and its
quality when it has one ("JPEG · 85"); keep format: "Keep format · copied unchanged" or "Keep format ·
saved again"; size: off → "Original size", else today's resize summary in words ("Longest side 2048",
"2000 × –", "12 MP", "50 %"); name: pattern + " · " + folder's last path component, or "Next to the
originals" when empty — as one string "\(pattern) · \(place)"; extras: a short description of what's
set ("Brightness +10", "Greyscale", "Bottom right, 60 %"), "On" when nothing more specific fits.

Done summary text (one string, plural-aware through the catalog): "\(converted) of \(total) images
converted in \(duration). \(bytesIn) in, \(bytesOut) out. Saved to \(folder)." — duration and sizes
through `Duration`/`ByteCountFormatStyle`; folder "next to the originals" when empty.

- [x] **Step 1: Write the failing tests:** `coreCardsAlwaysAdded`; `extrasFollowTheirSwitch`
  (`setAdded(true)` on `.orientation` sets `orientation.isOn`); `formatSummaryJPEGQuality`;
  `keepFormatSummarySaysCopied` / `…SaysSavedAgain`; `sizeSummaryOffIsOriginal`;
  `nameSummaryNextToOriginals`; `appliedLineInProcessingOrder` (crop + resize + watermark on →
  contains "crop", "size", "watermark" in that order); `appliedLineNilWhenNothingOn`;
  `reportCountsAndFolder` (3 results, 1 failed → string contains "2", "3");
  `failuresByName`; `newBatchKeepsFailedAndUnstarted` (`keep` with the failed and not-started URLs).
  Run tests with `-AppleLanguages` unset; compare numbers, not whole English sentences, where the
  wording is the builder's.
- [x] **Step 2: Run to see them fail.** `swift test --filter "BatchStepsTests|BatchReportTests|BatchInputListTests"`
- [x] **Step 3: Implement**, then make the app compile against `BatchCard` (views still the old ones,
  mapping `BatchStep` uses to `BatchCard`; `.rename` and `.safety` fold into `.name`).
- [x] **Step 4:** `swift test` → all pass.
- [x] **Step 5: Commit** `feat: batch cards, word summaries, the applied-order line and the run report in the core`

---

### Task 4: The setup window

**Files:**
- Modify: `Sources/Featherview/Batch/BatchView.swift`, `BatchStepViews.swift` (settings views become
  card bodies; the Output view splits into Format and the Name card's "Save to"), `BatchImagesColumn.swift`
  (empty state), `BatchPreview.swift` (min height, applied line), `BatchModel.swift` (`openCard`)
- Create: `Sources/Featherview/Batch/BatchCards.swift` (the card list, Add Step menu, folding)

**Interfaces:**
- Consumes: `BatchCard` (Task 3), `BatchSettings.changeFormat`, `resize.isOn`.
- Produces: `BatchModel.openCard: BatchCard?` (one open at a time; nil = all folded; default `.format`).

Layout (design "Layout" and "Cards"; values from `Theme`, add tokens there if missing):

- Toolbar: no mode picker; title "Batch Convert".
- Leading column: images. Empty: a prominent bordered "Choose Folder…" (feather accent, like the
  viewer's empty hint), "Add Files…" below it, then "or drop images here".
- Trailing: a scroll view of cards over the preview. Card header: number circle (core) or nothing
  (extras), name, summary trailing when folded, ✕ on extras (removes: `setAdded(false)`). Clicking a
  header toggles `openCard`. Under the cards: "Add Step" menu listing `BatchCard.extras`, the added
  ones disabled; picking one adds it and opens it.
- Format card body: "Change format" checkbox; when on, today's format picker + Options….
- Size card body: "Change size" checkbox (`resize.isOn`); when on, today's resize controls.
- Name card body: pattern field with placeholders, "Save to" (Next to the originals / folder path +
  Choose…), then today's Safety and dates controls under a small "Safety and dates" heading.
- Preview under the scroll view: min height 160 pt, the `appliedLine` under the pictures.
- Bottom bar: Presets ▾ leading; "Convert \(count) Images" trailing (`.keyboardShortcut(.return, modifiers: .command)`, disabled unless `canStart`).
- ⌘2, ⌘3, ⌘4 set `openCard` to format, size, name (hidden buttons, as the window does for other keys).
- The images `List` gets `.listStyle(.plain)` (Task 1: the sidebar style's flat-indentation check
  walks all rows on every insert, ~750 ms with 10,000 images), with a comment saying why.
- No card body may be wider than its column at the 960 pt minimum: long notes (Canvas "Negative
  values cut into the image") wrap under the field instead of beside it.

- [x] **Step 1: Build** the views to this list; remove the steps column.
- [x] **Step 2:** `swift build` clean (no new warnings); `swift test` passes.
- [x] **Step 3:** `scripts/bundle.sh debug` succeeds. The look is checked on screen in Task 6.
- [x] **Step 4: Commit** `feat: batch window starts with Choose Folder and numbered fold-open cards`

---

### Task 5: Running and done

**Files:**
- Modify: `Sources/Featherview/Batch/BatchRunView.swift`, `BatchView.swift`, `BatchModel.swift`, `BatchPreview.swift`

**Interfaces:**
- Consumes: `BatchReport` (Task 3), `BatchInputList.keep(_:)`, `openCard` (Task 4).
- Produces: `BatchModel.newBatch()`; `BatchModel.lastWritten: URL?` (the latest converted output,
  for the running preview).

- Running: the cards collapse to one line (all summaries joined " · "), then "\(done) of \(total)",
  a progress bar, "About … left" (today's), and the preview area shows `lastWritten` decoded off the
  main thread to fit the area (`ImageDecoder.decode(url, maxPixelSize:)`), with name, pixel size and
  file size; Pause/Resume and Stop replace the main button. No log list (Copy Log has it).
- Done: `BatchReport.summary` and the failure lines at the top of the settings area, Show in Finder
  (the output folder, or the first output's folder when "next to the originals") and Copy Log; the
  main button "New Batch" calls `newBatch()`: keeps failed and not-started inputs
  (`inputs.keep(...)`), clears results, back to setup with all settings. Adding images or changing a
  setting after a run also returns to setup (today's `clearFinished`).

- [x] **Step 1: Build** it; remove `BatchSummaryBar`.
- [x] **Step 2:** `swift test` passes; `swift build` clean.
- [x] **Step 3: Commit** `feat: batch run shows each written image and ends with a summary and New Batch`

---

### Task 6: Strings, translations, spec, screen check (main session)

- [ ] **Step 1:** `scripts/strings.sh`; translate every new key into the 29 other languages with the
  rules in `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` ("Translation tasks (5–10):
  the shared steps"); `swift test` (the catalog test needs all 30) passes.
- [ ] **Step 2:** Rewrite `docs/spec.md` "Batch window › Window" and "Mode and inputs" to the design
  (no mode; Change format / Change size; Next to the originals; keep-format failures; cards; running;
  done; New Batch).
- [ ] **Step 3 (screen, after the maintainer's go):** release build, window at 960 × 600 and at its
  default size, light and dark, English, German and Arabic:
  empty window (Choose Folder is the obvious first control); a folder of 48 JPEGs; each core card
  folds/unfolds, one at a time; Add Step adds Colour and Text, ✕ removes; with Text and Watermark
  open the preview keeps ≥ 160 pt; Change format off + nothing on → "copied unchanged" and the files
  are byte-identical; Change format off + Size → "saved again"; a run: progress, written images
  updating, rows ticking; done: summary sentence, failures by name, New Batch keeps the failed;
  an old preset (saved before this change) loads and produces the same names; every card open at
  960 pt keeps the window's content inside the window; 10,000 images: adding them, opening cards
  and adding a step answer within 100 ms p95 (Task 1's harness in `research/batch-timing/`, pointed
  at card headers instead of step rows).
- [ ] **Step 4:** Fix what this finds (each fix its own commit); tick the plan; commit
  `docs: batch window redesign done after manual QA`.
