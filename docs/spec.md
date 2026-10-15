# Featherview v1 — product spec

The only source of requirements. If something isn't here, it isn't in v1. Change this file
first, then the plan, then the code.

## Who it's for

People who want to look through folders of images on a Mac quickly: open one image, flip
through the rest with the keyboard, fix orientation, delete rejects, and batch-convert the
keepers. Especially people coming from Windows, where a fast viewer was one double-click away.

## Principles

1. **Instant.** Speed is the feature. See the performance budgets in `AGENTS.md`.
2. **Keyboard first.** Every viewer action works from the keyboard without modifier keys.
3. **Out of the way.** One window, the image, nothing else unless asked for.
4. **Never lose data.** Rotations are lossless and atomic; batch output never overwrites;
   delete moves to the Trash.
5. **Native.** Mac menus, full screen, Finder "Open With", drag and drop, Dark Mode.

## Viewer

- Opens a file from Finder (double-click if set as default, "Open With", drag onto the Dock
  icon), from ⌘O, or by dropping a file or folder onto the window.
- Opening a file loads every decodable image in the same folder, in Finder order
  (img2 before img10), hidden files skipped. Opening a folder starts at its first image.
- Supported formats: everything ImageIO decodes on the user's Mac (JPEG, PNG, HEIC, WebP,
  TIFF, GIF first frame, BMP, camera RAW, …). PDF is not an image here.
- Window title: `filename — 3 / 120`.
- Black background. Fit mode shrinks large images to the window and never enlarges small ones.
- The window keeps its size and position when the image changes; it never resizes itself to the
  image. Zoom changes the image inside the window, not the window.
- EXIF orientation is always applied.
- A file that can't be decoded shows "Can't open <name>"; browsing continues normally.

### Keys (no modifiers, viewer window focused)

| Key | Action |
|---|---|
| → ↓ Space Page Down | next image; past the last image, the next folder (see below) |
| ← ↑ Backspace Page Up | previous image; before the first, the previous folder |
| Home / End | first / last image |
| ← → ↑ ↓ when the image is larger than the window | pan instead of changing images |
| R / L | rotate right / left (lossless) |
| I | toggle info panel |
| F, Return | toggle full screen; Esc leaves full screen (and never quits the app) |
| 0 | zoom to fit |
| 1 | actual size (1 image pixel = 1 screen pixel) |
| + / − | zoom in / out (×1.1 steps, 5 %–1600 %) |
| F7 / F8 | move / copy the current file to a folder (see below) |

### Mouse and trackpad

- Double-click the image: toggle full screen.
- Two-finger scroll (or a mouse wheel) pans a zoomed image; it never changes images.

### Menu commands

⌘O Open…, ⌘⌫ Move to Trash, ⌘B Batch Convert…, ⇧⌘S Save As… (the current image in any writable format, with that format's options, orientation
applied, never overwriting without the standard Mac replace prompt), ⌘C Copy (the current image, full resolution,
orientation applied), ⌘Q Quit. Menus also list the single-key commands
(with the key in the title) so they are discoverable. Single keys are deliberately not menu
shortcuts, so typing in the batch window's text fields never triggers viewer actions.

### Rotate

Lossless: only the EXIF orientation tag changes. Supported for JPEG, HEIC and TIFF; other
formats show "Lossless rotation works with JPEG, HEIC and TIFF only". The file is rewritten
through a temp file and swapped in, so a failure (e.g. read-only folder) leaves the original
untouched and shows "Couldn't rotate <name>".

### Move to Trash

⌘⌫ moves the current file to the Trash (recoverable) and shows the following image.

### Info panel

Side panel listing whatever is present: dimensions (orientation applied), file size, camera,
lens, date taken, exposure, aperture, ISO, focal length. Missing values are left out.
Text is selectable.

### Moving past the end of a folder

Past the last image (→) or before the first (←), a keyboard-driven folder chooser appears over
the viewer, starting on the current folder. It lists "this folder again", the parent folder and
the current folder's subfolders, in Finder order, with each folder's image count once known.
→ or Space enters the selected folder, ← goes up a level, ↑ ↓ select, Return opens the first
image of the selected folder, Esc cancels and stays on the current image.

### Move / copy to folder (F7 / F8)

F7 (move) and F8 (copy) open a panel of 14 remembered destination folders. A single key picks
one: 1–9, 0 for 10, then B, C, D, E for 11–14; Return uses the highlighted slot. Each slot can be
set with "Choose…". Missing folders are created. A copy leaves the viewer as it is; after a move
the next image shows. Never overwrites: a clash gets " 2", " 3", … appended.

### Windows

Opening a file from Finder while a viewer window is open opens a new viewer window with its own
folder list.

## Batch window (⌘B)

### Mode and inputs

- Mode: Convert, Rename (copies with new names, no re-encode), or Convert and rename.
- Inputs: "Add Files…" (multi-select), "Use Viewer's Folder", "Add Folder…" with an optional
  "Include subfolders", Remove, Clear, Sort (by name, Finder order), Move up/down, and
  "Save List…"/"Load List…" (plain text, one path per line). Hidden and non-image files are
  skipped when adding folders.

### Output

- Output format: every format in "Formats" below that can be written. Each format has its own
  options (see "Format options"); the same options appear when saving from the viewer.
- Output folder chosen by the user (may be the input folder). `{folder}` in the output path
  stands for the input file's folder name.
- Rename pattern: `{name}` original name, `{n}` counter, `{n:3}` zero-padded counter, `{date}`
  date taken (YYYY-MM-DD, file date if missing). `/` and `:` become `-`. Empty pattern keeps the
  original name. The counter starts at 1 and advances only for files that succeed.
- "Preview Names" shows the first output names without writing anything.

### Per-image operations (applied in this order)

1. Crop: fixed rectangle (x, y, width, height) from a chosen corner or the centre.
2. Resize: width and/or height, longest side, shortest side, megapixels, or percentage. Options:
   keep aspect ratio (default on), don't enlarge smaller images (default on), don't shrink
   larger images, DPI value.
3. Rotate left/right, flip horizontal/vertical.
4. Colour: greyscale, negative, auto-adjust colours, brightness, contrast, gamma, saturation,
   per-channel balance, sharpen, blur, reduce colour depth.
5. Auto-crop uniform borders, canvas size, border, text overlay, watermark image.

Settings can be saved as named presets and loaded later.

### Safety and options

- Default: never overwrites anything: existing files, inputs and same-batch clashes
  (case-insensitive) get " 2", " 3", … appended.
- Optional "Replace existing files": replaced files move to the Trash first, never deleted.
- Optional "Move originals to Trash after converting" (only after their output is written).
- Optional "Keep file dates" (output gets the input's modification date).
- Optional "Recreate subfolders" in the output folder when inputs came from subfolders.
- Output pixels are upright (orientation applied, tag reset to 1). EXIF, GPS and IPTC metadata
  are kept.

### Running

- Runs in parallel on all cores but one. The window shows progress and a log: one line per file
  (output name or error), then "N converted, M failed". Stop (finishes files in flight, starts no
  more), Pause/Resume, and "Copy Log".
- A failing file never stops the batch and never leaves a partial output file.

## Settings (⌘,)

A standard Mac settings window with tabs. Every setting below has the default shown.

- Browsing: past the end of a folder: folder chooser (default) / loop this folder / stop; show
  hidden files (off); after Move to Trash or move to folder, show the next image (on); move,
  copy and trash sidecar files with the same name (`.xmp`, `.aae`, `.thm`) together (on).
- Viewer: background colour (black); checkerboard behind transparent images (on); remember the
  window's size and position (on); zoom step (10 %).
- Full screen: overlay text (off; template with `{name}`, `{folder}`, `{index}`, `{count}`,
  `{size}`, `{date}`); hide the pointer (on).
- Move / copy: the 14 destination slots; ask before each move / copy (off).
- Open with: up to 3 external apps, opened with ⌥1, ⌥2, ⌥3 on the current file.
- Formats: per-format defaults (see "Format options"), saved profiles.

## Formats

Format support is a headline feature. The lists are built at runtime from what macOS can do
(ImageIO), so a newer macOS adds formats without an app update; the app shows what it supports in
the About window.

- Read: everything ImageIO decodes, including JPEG, PNG, HEIC/HEIF, AVIF, JPEG XL, WebP, TIFF,
  GIF (first frame), BMP, ICO, ICNS, JPEG 2000, PSD, TGA, OpenEXR, Radiance HDR, SGI, PBM, DDS,
  DNG and camera RAW from all major makers. PDF is not an image here.
- Write (ImageIO): JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, JPEG 2000, PDF, PSD, TGA, ICO, ICNS,
  OpenEXR, PBM.
- Write (own encoders, pure Swift, no dependency): PGM, PPM, QOI, PCX.
- Write (open-source encoder, per `AGENTS.md`): WebP (libwebp, BSD).
- Writing JPEG XL is v2 (needs libjxl, a large C++ build). Reading JPEG XL works in v1 via ImageIO.

### Format options

| Format | Options |
|---|---|
| JPEG | quality 1–100 (default 80), progressive, no chroma subsampling, keep EXIF/IPTC/XMP/comment (default on), target file size in KB |
| HEIC, AVIF | quality 1–100 (default 80), lossless, keep metadata (default on) |
| PNG | compression effort fast / default / best, interlaced |
| TIFF | compression none / LZW / PackBits / JPEG / ZIP, keep all pages |
| GIF | interlaced |
| JPEG 2000 | quality 1–100, lossless |
| WebP | quality 1–100 (default 75), lossless, effort 0–6 (default 4), preset photo / picture / drawing / icon / text |

Orientation is always applied to the pixels and the tag reset to 1 (not an option). Options are
remembered per format and can be saved as named profiles.

## Not in v1

See "Out of scope for v1" in `AGENTS.md`.

## Open decisions for the maintainer

- License (MIT, Apache-2.0 or GPL-3.0).
- App icon (no cat imagery).
- Signing and notarization for public releases (needs an Apple Developer account).
