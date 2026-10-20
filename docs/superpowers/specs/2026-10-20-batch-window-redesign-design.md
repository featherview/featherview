# Batch window redesign — design

## Why

The maintainer, opening the batch window to convert a folder: "I don't know what control to use
first." The current window (spec "Batch window › Window") shows everything at once: an empty images
column, a mode menu, a list of eleven steps with summaries and a settings card, with nothing saying
where to start. The step column is fixed at 230 pt, so longer languages cut its summaries (German
"Gleiches Format"). The maintainer knows the reference viewer's batch dialog from 20 years of use,
but wants this window to be clear on its own, not a copy (and the clean-room rules forbid copying
its layout anyway).

What the maintainer does in a batch, in this order: pick a folder, then the format, then the size.
Renaming matters as much. Everything else (crop, rotate, colour, filters, canvas, border, text,
watermark) is rarer.

Success: someone opening the window for the first time knows the first move without reading
anything, and a typical batch (folder → format → size → name → convert) needs no hunting.

## Goals

- One obvious first move in an empty window.
- The window follows the user's order: images, format, size, name.
- Rare steps out of sight until added; the window never fills up with unused controls.
- The before/after preview always visible while setting up.
- While running: clear progress and the output as it's written. After: a summary in sentences.

## Non-goals

- No change to what a batch can do (formats, operations, options, naming placeholders,
  never-overwrite rules, multi-page handling): spec "Batch window" sections other than "Window"
  and "Mode and inputs" stay as they are.
- No change to the batch engine (`BatchConverter`, `ImagePipeline`, `PipelineRender`) beyond what
  the settings mapping below needs.
- No wizard (Back / Next pages) and no popovers for step settings: both were shown and rejected.

## Anti-goals (a failure even if it works)

- A window where the first-time user still has to guess where to start.
- Settings that unfold until the preview disappears.
- "Keep format" silently re-compressing JPEGs without saying so.
- Presets saved with the current window that no longer load the same batch.

## The design (decided with the maintainer; mockups in `.superpowers/brainstorm/`, not committed)

### Layout

Two columns plus a bottom bar, window minimum width unchanged (960 pt).

- **Leading: Images.** The input list as today (thumbnail, name, pixel size, file size, pages;
  drop target; add / remove / sort / more menu). When empty it shows one prominent
  **Choose Folder…** button (the first move), with Add Files… and "or drop images here" beneath.
- **Trailing: settings, then preview.**
  - Four core cards, numbered by the user's order and shown always:
    **2 Format · 3 Size · 4 Name** — the images list is step 1. (Name includes where to save.)
  - **Add Step ▾** below the cards: a menu of the eight extra steps (Crop, Rotate & Flip, Colour,
    Filters, Canvas, Border, Text, Watermark); steps already added are disabled in it. Picking one
    adds its card below the core cards (in the order of the menu), opened. Each added card has
    an ✕ that removes it (and turns the operation off).
  - **The before/after preview** under the settings: original and output side by side with their
    pixel sizes, the first output names beside them, and one line "Applied: crop → size →
    watermark" naming the steps in their real processing order (spec "Per-image operations").
    Minimum height 160 pt; when the cards need more room the settings area scrolls, the preview
    never shrinks below that.
- **Bottom bar:** Presets ▾ at the leading edge; the main button at the trailing edge.

### Cards

- Every card (core and added) folds and unfolds inline. One card is open at a time: opening one
  folds the others. A folded card is one line: its name and a summary in words ("JPEG · 85",
  "Longest side 2048", "trip-{n:3} · Desktop/Out", "Brightness +10").
- Unfolded cards use the existing grouped-card form (labels leading, controls trailing) and the
  existing per-step settings views.
- Keyboard: ⌘2, ⌘3, ⌘4 unfold Format, Size, Name (matching their numbers); ⌘↩ runs, as today.

### Format and the end of the mode menu

The toolbar's mode menu (Convert / Rename / Convert and rename) goes away.

- The Format card has a **Change format** checkbox (default on). On: the format menu and its
  Options… button appear as today. Off: files keep their own format.
- With Change format off, a file whose pixels don't change (no Size, no added step that changes
  pixels) is **copied byte for byte** under its new name (today's "Rename" mode). A file whose
  pixels change is saved again in its own format with that format's remembered options.
- With Change format off, a file whose pixels change but whose own format can't be written (camera
  RAW, multi-page DCX, the read-only own formats such as XCF or PSP) **fails** with a short reason
  naming the file ("Can't save IMG_0412.CR3 in its own format"); the rest of the batch continues.
  No fallback format. *(Maintainer's decision.)*
- The Format summary says which happens: "Keep format · copied unchanged" or "Keep format ·
  saved again (JPEG 90)".
- The Name card always applies; its pattern defaults to `{name}` (names unchanged).
- The Size card has a **Change size** checkbox (default off; maps to today's resize on/off), the same
  pattern as Change format. Off: sizes unchanged. *(Builder's question; settled by Claude.)*
- The Name card's "Save to" is **Next to the originals** or a chosen folder, for every batch (old
  presets with an empty folder load as Next to the originals). With `{name}`, the same format and
  the originals' folder, never-overwrite adds " 2", as today's Rename mode. *(Settled by Claude.)*
- An added step is on, and counts as changing pixels even when its values happen to change
  nothing; the Format summary then says "saved again". Rotate & Flip gets a stored on/off flag
  (today it has none), so an added but untouched card survives a reload; decoding of older
  settings tolerates its absence. *(Settled by Claude.)*
- "Safety and dates" (never overwrite is fixed; keep file dates, copy sidecars …) becomes a
  row inside the Name card, not a separate step.

Mapping from today's settings (core, tested):

| Today | New |
|---|---|
| mode `convert` | Change format on; Name pattern `{name}` (convert mode ignored the pattern) |
| mode `rename` | Change format off; no operations on; pattern as saved |
| mode `convertAndRename` | Change format on; pattern as saved |

Saved presets and the remembered last settings load through this mapping, so an old preset
produces the same files as before.

### Running

- Pressing **Convert N Images** (N = list count) starts the run. The cards fold into one
  summary line (they can't change mid-run).
- Under it: "23 of 48", a progress bar, "about 1 min left".
- The preview area shows the image just written (with its name, pixel size and file size),
  replaced as each finishes.
- Image rows tick off (waiting, working, done, failed) as today.
- The main button is replaced by **Pause** and **Stop**.

### Done

- A summary in sentences at the top of the settings area: "47 of 48 images converted in 1 min
  12 s. 210 MB in, 96 MB out. Saved to Desktop/Out." then every failure by file name with a short
  reason ("IMG_0412.heic — can't read the file"). Buttons: Show in Finder, Copy Log.
- The main button becomes **New Batch**: it removes the images that converted from the list,
  keeps the failed ones (so they can be fixed and retried), keeps all settings, and returns the
  window to setup. Adding images or changing a setting also returns to setup; the button then
  reads "Convert N Images" again.

## Constraints

- AGENTS.md: SwiftUI, Swift 6, macOS 14 minimum; tokens from `Theme.swift`, no hard-coded colours,
  radii or durations; leading/trailing layout (right-to-left mirrors); all text translatable,
  no sentences built from pieces (the summary sentences are whole catalog strings with
  placeholders); user-facing errors name the file.
- The 30 languages: every new string goes through `scripts/strings.sh` and needs all 30
  translations before the catalog test passes.
- Performance: the window with 10,000 images must not stall when a card opens, a step is added or
  a setting changes (today clicking a step with 10,000 images stalls the app for seconds; that bug
  is fixed before this work, separately).
- Clean-room: our own design; nothing taken from the reference viewer's dialog layout.

## Left to the builder

- Exact spacing, typography, animation of folding (within `Theme` motion tokens; Reduce Motion
  gives plain cuts).
- How the summary strings are worded per step (short, in words, translatable).
- Whether added cards keep their order of adding or the menu's order (decided: the menu's order;
  the builder may revisit if it reads oddly).
- The empty-window "Choose Folder…" button's exact look (a prominent bordered button, feather
  accent, like the viewer's empty hint).

## Spec and plan follow-up

- `docs/spec.md` "Batch window › Window" and "Mode and inputs" are rewritten to this design.
- A plan (superpowers:writing-plans) after this document is approved; its first task is the
  10,000-image stall fix, its last a screen check in light, dark, German and Arabic.
