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
- A folder without images shows "No images in <folder>"; ← / → still go to other folders.
- Opening a file loads every decodable image in the same folder, in Finder order
  (img2 before img10), hidden files skipped. Opening a folder starts at its first image.
  Images are recognised by file extension only (scanning never opens a
  file); `.jfif`, `.jif` and `.jfi` count as JPEG; the file the user opened is always in the list,
  even if hidden or of an unknown extension; symlinked folders are followed; folders and broken
  links with image names are skipped.
- Supported formats: everything ImageIO decodes on the user's Mac (JPEG, PNG, HEIC, WebP,
  TIFF, GIF first frame, BMP, camera RAW, …), plus PDF (see "Formats").
- Window title: `filename — 3 / 120`; for a multi-page file `filename — page 2 / 3 — 3 / 120`.
  A multi-page file always opens on page 1.
- Black background. Fit mode shrinks large images to the window and never enlarges small ones.
- The window keeps its size and position when the image changes; it never resizes itself to the
  image. Zoom changes the image inside the window, not the window.
- EXIF orientation is always applied.
- Status bar (milestone 3): one line along the bottom of the window, on by
  default, showing the image's pixel size, zoom %, file size, position N / M and the file's
  modification date. View › Hide Status Bar hides it (remembered). Hidden in full screen. Our own
  order, wording and layout (leading-aligned, system small font).
- Liquid Glass (milestone 3): on macOS 26 and later the folder chooser, the
  F7/F8 panel and on-image messages use Liquid Glass; earlier systems keep the current material.
  Minimum macOS stays 14.
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
| ⌥→ / ⌥← | next / previous page of a multi-page file (TIFF, …); nothing past either end |
| F7 / F8 | move / copy the current file to a folder (see below) |
| ⌦ (forward delete) | Move to Trash, like ⌘⌫ |
| O / B / M | Open… / Batch Convert… / minimise the window (as ⌘O / ⌘B / ⌘M) |
| P / A / S | Preferences / About / Save As…, each added with its feature (milestones 2–3) |

Single keys for commands match the reference viewer, for people switching over; the ⌘ shortcuts stay for Mac users.

### Mouse and trackpad

- Double-click the image: toggle full screen.
- Dragging pans a zoomed image (the image follows the pointer); it does nothing when the image
  fits. No selection rectangle.
- Right-click (or Control-click) opens a context menu with the window's actions: Copy, Rotate
  Left / Right, Move to Folder…, Copy to Folder…, Move to Trash, Show in Finder, Open With.
- Two-finger scroll (or a mouse wheel) pans a zoomed image; it never changes images.

### Toolbar

For mouse users, the viewer window has a standard macOS toolbar: previous,
next, rotate left, rotate right, zoom out, zoom to fit, zoom in, info panel, Move to Trash, plus previous / next page
for a multi-page file only. Each button does what its key does and has a tooltip naming that key. View › Hide Toolbar hides it
(remembered), and View › Customize Toolbar… changes it, as in any Mac app. Hidden in full screen.
Mac SF Symbols, never icons taken from another viewer.

### Menu commands

⌘O Open…, ⌘⌫ Move to Trash, ⌘B Batch Convert…, ⇧⌘S Save As… (the current image in any writable format, with that format's options, orientation
applied, never overwriting without the standard Mac replace prompt; afterwards the window shows the saved file in its folder; if Featherview can't read the format it saved, the window stays on the original), ⌘C Copy (the current image, full resolution,
orientation applied), ⌘Q Quit. Menus also list the single-key commands
(the single key in the shortcut column, also for commands that have a ⌘ shortcut, which keeps
working) so they are discoverable. Single keys are menu shortcuts only while a
menu is open, so typing in the batch window's text fields never triggers viewer actions.

### Rotate

Lossless: only the EXIF orientation tag changes. Supported for JPEG, HEIC and TIFF; other
formats show "Lossless rotation works with JPEG, HEIC and TIFF only". The file is rewritten
through a temp file and swapped in, so a failure (e.g. read-only folder) leaves the original
untouched and shows "Couldn't rotate <name>".
In a multi-page TIFF only page 1 can be rotated: ImageIO can't change a later page's tag without
re-encoding every page, so pages 2 and on show "Only page 1 of <name> can be rotated losslessly"
and the file stays untouched.

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

## Batch window (B, ⌘B)

### Mode and inputs

- Mode: Convert, Rename (copies with new names, no re-encode), or Convert and rename.
- Inputs: "Add Files…" (multi-select), "Use Viewer's Folder", "Add Folder…" with an optional
  "Include subfolders", Remove, Clear, Sort (by name, Finder order), Move up/down, and
  "Save List…"/"Load List…" (plain text, one path per line). Hidden and non-image files are
  skipped when adding folders.
- Order (like the reference viewer): each add appends to the end of the list,
  the added files in Finder order; earlier entries keep their place. Output numbers follow the
  list order.

### Output

- Output format: every format in "Formats" below that can be written. Each format has its own
  options (see "Format options"); the same options appear when saving from the viewer. In both,
  an "Options…" button next to the format opens them, so the window and save panel stay short
  (as in the reference viewer).
- Multi-page input (TIFF, PDF, DCX): TIFF with "keep all pages" and PDF output get every page;
  any other format gets the first page, and the log line says so ("page 1 of 297"), so no page
  is dropped silently. No file per page.
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

## Preferences (⌘,)

The menu calls it "Preferences…", not macOS's "Settings…", so it matches its single key P.

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

## About window

Our own About window replaces the plain standard panel. Mac-like, one small
window, nothing to configure.

- The feather icon, "Featherview", version and build (`0.1.0 (1)`), the one-line description.
- Links: website, source code on GitHub, report a problem (GitHub issue), all opening the browser.
- "Supported formats": two lists, read and write, built at runtime from ImageIO plus our own
  encoders (see "Formats"), with the macOS version they come from.
- "MIT License" and "Acknowledgements": the licence text of every bundled library (libwebp), each
  in a scrollable sheet. Copyright line.
- A "Copy" button copies version, macOS version and Mac model as text, for bug reports.
- Translated like the rest of the UI; no third-party names except in the acknowledgements.

## Languages

The UI is translated into the 30 most widely spoken languages that macOS
offers. The app follows the system language, and System Settings › Language & Region › Applications
can set it per app (no setting of our own).

English (source), Chinese Simplified, Chinese Traditional, Hindi, Spanish, Arabic, French,
Portuguese (Brazil), Russian, Indonesian, German, Japanese, Turkish, Vietnamese, Korean, Italian,
Thai, Polish, Ukrainian, Malay, Dutch, Romanian, Greek, Hungarian, Swedish, Czech, Catalan,
Hebrew, Danish, Finnish.

"Offers" means a macOS system language (checked against Finder's localizations on macOS 27):
of the Indian languages only Hindi qualifies; Bengali, Urdu, Marathi, Telugu, Tamil, Gujarati,
Kannada and Malayalam are iOS-only.

- One String Catalog (`Localizable.xcstrings`); every user-facing string goes through it,
  including error messages and the batch log.
- Arabic and Hebrew mirror the whole window layout: info panel, toolbars, sidebars, batch window
  columns, lists, progress bars and direction-bearing symbols (chevrons, back/forward) all flip
  to right to left. Use leading/trailing, never left/right, in layout code; AppKit views use
  `userInterfaceLayoutDirection`. Never mirrored: the image itself, rotate symbols and their
  direction (rotate left stays counter-clockwise), crop coordinates.
- Numbers, sizes, dates and units use system formatters, never hand-built strings.
- Keyboard shortcuts stay the same in every language, except ← and → in Arabic and Hebrew:
  they follow the mirrored screen, so ← is next image and → is previous (the "next" chevron
  points left there). ↑ ↓ Space Page Up/Down Backspace are unchanged; panning a large image
  stays physical (← pans left).
- File names produced by rename templates are not translated.

## Formats

Format support is a headline feature. The lists are built at runtime from what macOS can do
(ImageIO), so a newer macOS adds formats without an app update; the app shows what it supports in
the About window.

- Read: everything ImageIO decodes, including JPEG, PNG, HEIC/HEIF, AVIF, JPEG XL, WebP, TIFF,
  GIF (first frame), BMP, ICO, ICNS, JPEG 2000, PSD, TGA, OpenEXR, Radiance HDR, SGI, PBM, DDS,
  DNG and camera RAW from all major makers.
- PDF (milestone 3, like the reference viewer): a PDF is browsed like a
  multi-page image. Core Graphics renders each page on white at 144 dpi (an A4 page is
  1190 × 1684 pixels; fit mode renders it straight at the window's size), opening on page 1; ⌥← / ⌥→ step pages and the page shows in the title and status bar.
- Read, formats ImageIO can't read, which Featherview decodes itself:
  - SVG through AppKit (`NSImage` renders it; ImageIO doesn't), rasterised at the size shown.
  - Own decoders, pure Swift, no dependency (milestone 3): QOI, PCX (and multi-page DCX), XBM,
    XPM, WBMP, Sun Raster (RAS), IFF/LBM (ILBM, incl. HAM and EHB).
  - Layered app formats, shown flattened (own milestone after 3): PSB (its stored composite
    image), XCF (GIMP), PDN (Paint.NET), PSP (Paint Shop Pro). Where the file stores a composite
    or thumbnail at full size it is used; otherwise visible layers are composited with normal
    blending and their opacity, and other blend modes are listed as a known limit.
  - Every own decoder goes through the same paths as ImageIO's: folder listing by extension,
    downsampled decode at screen size, batch input, info panel (dimensions only). A file it
    can't read shows "Can't open <name>" like any other.
- Finder previews (after the own decoders): a Quick Look preview and
  thumbnail extension for the formats only Featherview reads, reusing its decoders, so Finder,
  Quick Look (Space) and open panels show them too. Formats ImageIO reads are left to macOS.
- Write (ImageIO): JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, JPEG 2000, PDF, PSD, TGA, ICO, ICNS,
  OpenEXR.
- Write (own encoders, pure Swift, no dependency): PBM, PGM, PPM, QOI, PCX. PBM is real 1-bit
  binary PBM, black and white at a 50% threshold (ImageIO's PBM writer writes
  colour ASCII PPM under the .pbm name).
- Write (open-source encoder, per `AGENTS.md`): WebP (libwebp, BSD).
- Writing JPEG XL is v2 (needs libjxl, a large C++ build). Reading JPEG XL works in v1 via ImageIO.
- HDR display (milestone 3): images with HDR data (gain-map HEIC/JPEG from
  phones, HDR AVIF/HEIC, OpenEXR, Radiance HDR) show with their extra brightness on screens that
  support it, on macOS 15 and later. Only those images decode at 16 bits (twice the memory); all
  others stay 8-bit, so browsing speed and memory don't change. On macOS 14 or an SDR screen they
  show as SDR. Batch output and Save As keep writing SDR unless the target format keeps the HDR data:
  HEIC and AVIF output of an HDR photo keeps its HDR (gain map).

### Format options

| Format | Options |
|---|---|
| JPEG | quality 1–100 (default 80), progressive, keep EXIF/IPTC/XMP/comment (default on), target file size in KB |
| HEIC, AVIF | quality 1–100 (default 80; 100 is the best ImageIO does, not lossless), keep metadata (default on) |
| PNG | interlaced |
| TIFF | compression none / LZW / PackBits / JPEG / ZIP, keep all pages |
| JPEG 2000 | quality 1–100 (default 90), lossless (default) |
| PDF | one page per image at the image's size; JPEG quality 1–100 for the image (default 95) or lossless (paper sizes later) |
| GIF, TGA, BMP, PSD, OpenEXR, PBM | none |
| ICO, ICNS | none; the image is scaled to fit a transparent square of 256 px (ICO) or 512 px (ICNS), or the next allowed size up for smaller images (16, 32, 128, 256, 512), never enlarged beyond it |
| WebP | quality 1–100 (default 75), lossless, effort 0–6 (default 4), preset photo / picture / drawing / icon / text |

After testing ImageIO on macOS 27: it can't write JPEG without chroma subsampling
(except at quality 100), lossless HEIC/AVIF, PNG compression levels or interlaced GIF, so those
options are not offered. ImageIO's GPU texture formats (KTX, KTX2, ASTC, PVR, ATX, DDS) and HEIC
sequences are not offered for writing; any other type a newer macOS adds appears automatically.

Orientation is always applied to the pixels and the tag reset to 1 (not an option). Options are
remembered per format and can be saved as named profiles.

## Not in v1

See "Out of scope for v1" in `AGENTS.md`.

## Distribution

Releases are ad-hoc signed and not notarized (no paid Apple Developer
account). README.md tells users how to open the app the first time. Revisit if someone sponsors
the $99/year Apple Developer Program; then sign with Developer ID and notarize.

## App icon

The feather mark, `Resources/AppIcon.svg` (source of `AppIcon.icns` and the
website favicon). No cat imagery.
