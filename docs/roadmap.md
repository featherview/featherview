# Featherview v1 roadmap

`docs/spec.md` says what v1 is. This file splits it into five milestones, each shippable and
testable on its own. Each milestone gets its own detailed plan in `docs/superpowers/plans/`,
written (superpowers:writing-plans) when the previous milestone is merged, so it can use the real
interfaces instead of guessed ones. Run a milestone's plan wave by wave with the `plan-wave`
workflow.

Milestones marked **observe first** have reference-viewer behaviour not yet recorded in
`docs/parity.md`; run the `observe-reference` skill for those items before writing the plan.

| # | Milestone | Plan | Status |
|---|---|---|---|
| 1 | Core viewer and batch | `docs/superpowers/plans/2026-10-15-featherview-v1.md` | planned |
| 2 | Viewer complete | to write after 1 | — |
| 3 | Formats and Save As | to write after 2 | — |
| 4 | Batch complete | to write after 3 | — |
| 5 | WebP output | to write after 3 (independent of 4) | — |

## 1. Core viewer and batch

Folder scanning, bounded navigation, decoding at screen size with an 8-image cache and
prefetch, metadata, lossless rotate, Move to Trash, info panel, fit / actual size / ×1.1 zoom,
full screen (F, Esc), drag and drop, ⌘O; batch with JPEG/PNG/HEIC/TIFF, quality, limit size,
`{name}`/`{n}` rename, never-overwrite planning, parallel run. Meets the performance budgets.

## 2. Viewer complete

Spec: "Viewer" (all of it), "Settings", "Windows".

- Folder chooser past either end (keyboard-driven, parent and subfolders, image counts).
  `ImageList.next()` returning false is the hook. Core: `FolderTree` (siblings, parent, children,
  image counts, Finder order).
- Arrow keys pan when the image is larger than the window; two-finger scroll pans; never
  navigates.
- Return and double-click toggle full screen; ⌘C copies the image (full size, upright).
- F7 / F8 move / copy with 14 destination slots (1–9, 0, B–E), " 2" suffixes, next image after a
  move. Core: `DestinationSlots` (persisted), `FileMover` (never overwrite, sidecars).
- Sidecar files (`.xmp`, `.aae`, `.thm`) move, copy and trash with their image.
- One viewer window per file opened from Finder (`WindowGroup(for: URL.self)`).
- Settings window (⌘,) with every setting in the spec, persisted in `UserDefaults`.
- **Observe first:** mouse dragging in the window, right-click in the window, opening a folder
  directly, multi-page TIFF browsing.

## 3. Formats and Save As

Spec: "Formats", "Format options", ⇧⌘S Save As.

- Runtime format registry from `CGImageSourceCopyTypeIdentifiers` /
  `CGImageDestinationCopyTypeIdentifiers`; shown in About.
- Per-format option models and encoders for every ImageIO-writable format (JPEG target file
  size by binary search on quality).
- Own pure-Swift encoders: PGM, PPM, QOI, PCX (golden-file tests against hand-computed bytes).
- Save As from the viewer with the format's options; options remembered per format, profiles.
- Batch output uses the registry (replaces the fixed list from milestone 1).
- **Observe first:** option dialogs of GIF, JPEG 2000, TGA, PDF output; HEIC/AVIF/RAW reading in
  the reference viewer (for the parity record).

## 4. Batch complete

Spec: "Batch window (⌘B)" (all of it).

- Modes convert / rename / both; rename-only copies without re-encoding.
- Input list: Add Folder with subfolders, Sort, Move up/down, Save / Load List.
- Rename: `{date}`, `{folder}`, counter advances only on success (the planner from milestone 1
  assigns names up front; this milestone assigns the counter as files finish, still
  clash-checked), Preview Names.
- Operation pipeline in spec order: crop, resize (all modes), rotate / flip, colour operations,
  borders / canvas / text / watermark. Core Image where it fits; each operation unit-tested on
  `Fixtures` images.
- Presets; Replace existing (to Trash), Move originals to Trash, Keep file dates, Recreate
  subfolders.
- Stop, Pause / Resume, Copy Log.
- **Observe first:** the sub-dialogs of canvas size, text overlay, watermark, border, and
  "more effects"; the batch preview image.

## 5. WebP output

Spec: "Write (open-source encoder)". libwebp built from source as a SwiftPM C target, loaded
only when writing WebP; WebP options (quality, lossless, effort, preset). Verify no change to
launch time and memory budgets. Record libwebp and its licence in README.md.

## v2 (not in v1)

JPEG XL writing (libjxl), thumbnail browser, anything in "Out of scope for v1" in `AGENTS.md`.
