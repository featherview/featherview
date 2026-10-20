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
  TIFF, GIF (first frame; animation in v2), BMP, camera RAW, …), plus PDF (see "Formats").
- Window title: `filename — 3 / 120`; for a multi-page file `filename — page 2 / 3 — 3 / 120`.
  A multi-page file always opens on page 1.
- The whole app is light or dark: Appearance in Preferences is System (the default), Light or Dark.
  The background is Graphite (#1c1c20, the app icon's tile) in dark and Grey (#e7e7ec) in light; no
  other colours. Fit mode shrinks large images to the window and never enlarges small ones.
- The canvas fills the whole window, under the toolbar and the status strip. Fit mode keeps the
  image clear of both (it fits the area between them); a zoomed or panned image slides under them,
  so the glass takes its colour from the picture. The system's scroll edge effect dims the picture
  under the toolbar, so its title and buttons stay readable over any picture.
- The window keeps its size and position when the image changes; it never resizes itself to the
  image. Zoom changes the image inside the window, not the window.
- EXIF orientation is always applied.
- Status bar (milestone 3): one line along the bottom of the window, on by
  default, showing the image's pixel size, zoom %, file size, position N / M and the file's
  modification date. View › Hide Status Bar hides it (remembered). Hidden in full screen. Our own
  order, wording and layout (leading-aligned, system small font, tabular figures). It floats as a
  slim rounded strip a few points inside the window's bottom edge, over the canvas.
- Liquid Glass (milestone 3, own look): on macOS 26 and later the toolbar, the status strip, the
  folder chooser, the F7/F8 panel and on-image messages use Liquid Glass; macOS 14 and 15 use the
  system's normal material in the same shapes, so no layout depends on glass. Minimum macOS stays 14.
- An empty window (nothing opened yet) shows the feather mark above "Open an image or drop a folder
  here" and the keys ⌘O and O, centred.
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
- Two-finger scroll (or a mouse wheel) pans a zoomed image.
- Pinch zooms in and out about the pointer, following the fingers (no animation), within the
  same 5 %–1600 % as + / −.
- Swiping sideways changes images the way the Mac swipes between pages: with two fingers (or three,
  per the trackpad setting), only while the image has nothing to pan sideways; a swipe goes the way of
  the arrow key it moves towards (mirrored in right-to-left languages). A mouse wheel never changes images.

### Toolbar

For mouse users, the viewer window has a standard macOS toolbar: previous,
next, rotate left, rotate right, zoom out, zoom to fit, zoom in, info panel, Move to Trash, plus previous / next page
for a multi-page file only. Each button does what its key does and has a tooltip naming that key. View › Hide Toolbar hides it
(remembered), and View › Customize Toolbar… changes it, as in any Mac app. Hidden in full screen; it slides in with the menu bar when the pointer is at the top (macOS 15 and later).

"Hide toolbar and status bar while viewing" (Preferences › Viewer, off): in a window, once the
pointer has rested over the picture for 2 s, the toolbar and status strip fade out (200 ms). Moving
the pointer, reaching the window's top edge, or any key except the browsing keys (← → Space
Backspace Page Up/Down Home End) brings them back at once; browsing keys keep them hidden. Every
toolbar command is also in the menus, so hiding never takes a command away.
Mac SF Symbols, never icons taken from another viewer.

### Menu commands

⌘O Open…, ⌘⌫ Move to Trash, ⌘B Batch Convert…, ⇧⌘S Save As… (the current image in any writable format, with that format's options, orientation
applied, never overwriting without the standard Mac replace prompt; afterwards the window shows the saved file in its folder; if Featherview can't read the format it saved, the window stays on the original), ⌘C Copy (the current image, full resolution,
orientation applied), ⌘Q Quit. Menus also list the single-key commands
(the single key in the shortcut column, also for commands that have a ⌘ shortcut, which keeps
working) so they are discoverable. Single keys are menu shortcuts only while a
menu is open, so typing in the batch window's text fields never triggers viewer actions.

The app menu has Check for Updates… below About (see "Updates"). The Help menu has Report a Bug…:
it opens the browser at a new GitHub issue from the repo's bug report form
(`.github/ISSUE_TEMPLATE/bug_report.yml`), with Featherview version and build, macOS version and Mac
model filled in; the person describes what happened.

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

### Default viewer

Featherview never makes itself the default app on its own: its document types stay rank Alternate.
It asks instead.

- Once, at the first launch from an Applications folder (`/Applications` or `~/Applications`, not
  from the disk image, `build/` or a translocated copy), and only while Preview or no app opens
  JPEG: a dialog "Open your images with Featherview?", "Featherview can open your images instead
  of Preview. You can change this later in Preferences › Browsing.", buttons "Use Featherview"
  (default) and "Not Now". Either answer ends the asking; it never comes back by itself.
- "Use Featherview" makes it the default for every image type it reads whose default is Preview
  or no app. Types another app opens (Photoshop for PSD, GIMP for XCF, an editor for SVG) stay
  with that app, and PDF always stays with its app: Featherview shows PDFs as images, it isn't a
  PDF reader.
- Preferences › Browsing, group "Default app": a line saying which app opens JPEG now, and the
  button "Use Featherview for Images" (the same action; off while Featherview opens every type it
  would take). Undo is Finder's Get Info › Open with › Change All.
- If macOS refuses some types, one sentence: "Featherview couldn't become the default for HEIC
  and WebP." (the types' extensions, a list from the system formatter). Nothing else changes.

## Look

Featherview looks like a Mac app with a few touches of its own; the app icon (a warm feather on a
dark tile) carries the identity.

- Colour: controls, selection and focus use the system accent colour, Start included. The feather
  colours (#ffc766 to #ff7a59) appear only in the About window, the empty-window hint and the disk
  image.
- Type: the system font everywhere; tabular figures wherever numbers change in place (status strip,
  batch progress and log).
- Motion: browsing is instant (no crossfade). A zoom step animates in 120 ms, the info panel slides
  in 180 ms, the hidden bars fade in 200 ms. With Reduce Motion these are plain cuts.

## Batch window (B, ⌘B)

### Window

Two columns and a bottom bar, titled "Batch Convert":

- Images (leading, step 1): the input list with a small thumbnail, name, pixel size, file size
  and page count per file; files and folders can be dropped on it; add (menu: Add Files…, Add
  Folder…, Add Folder with Subfolders…, Use Viewer's Folder), remove, Sort and a menu with Move
  up/down, Save List… and Load List…. When empty it shows one prominent **Choose Folder…** button,
  with Add Files… and "or drop images here" beneath it.
- Settings (trailing) as numbered cards that are always there: **2 Format**, **3 Size**,
  **4 Name**. Below them **Add Step**, a menu of the eight extra steps (Crop, Rotate & Flip,
  Colour, Filters, Canvas, Border, Text, Watermark; steps already added are disabled in it).
  Picking one adds its card below the core cards, in the menu's order, opened; its ✕ removes it
  and turns the step off. An added step is on.
- One card is open at a time; opening one folds the others. A folded card is one line: its name
  and a summary in words ("JPEG · 85", "Longest side 2048", "trip-{n:3} · Out", "Brightness
  +10"). ⌘2, ⌘3 and ⌘4 open Format, Size and Name. Cards use the same grouped form as
  Preferences (labels leading, controls trailing).
- Under the cards a live preview of the selected input (original and output side by side with
  their pixel sizes, small, rendered off the main thread, never blocking typing), the first
  output names, and one line naming the steps that are on in their processing order ("Applied:
  crop → size → watermark"). The preview keeps at least 160 pt; the cards scroll instead.
- Bottom bar: Presets at the leading edge; **Convert N Images** (⌘↩) at the trailing edge.
- Running: the cards give way to one line with every card's summary, "n of N", a progress bar,
  the time left, and the image just written (name, pixel size, file size). Each input row shows
  its state (waiting, working, done with its output name, failed). Pause/Resume and Stop replace
  the main button.
- Done: one sentence ("47 of 48 images converted in 1 minute, 12 seconds. 210 MB in, 96 MB out.
  Saved to ~/Desktop/Out."), then every failed file with its reason, Show in Finder and Copy
  Log. The main button becomes **New Batch** (⌘↩): it removes the converted images from the list,
  keeps the failed and unstarted ones, keeps all settings and returns to setup. Adding images or
  changing a setting also returns to setup.

### Format, size and inputs

- Format card: **Change format** (default on) shows the output format and its Options… button.
  Off: each file keeps its own format. Then a file whose pixels don't change (Change size off, no
  step added) is copied byte for byte under its new name; a file whose pixels change is saved
  again in its own format with that format's remembered options. A file whose own format can't
  be written (camera RAW, DCX, read-only formats such as XCF or PSP) fails with "Can't save
  IMG_0412.CR3 in its own format"; there is no fallback format.
- Size card: **Change size** (default off) shows the resize settings below.
- Presets and the remembered settings saved before these cards existed load as the same batch:
  the old Convert mode as Change format on with the pattern `{name}`; Rename as Change format off
  with no step on; Convert and rename as Change format on with its pattern.
- Inputs: "Add Files…" (multi-select), "Use Viewer's Folder", "Add Folder…", "Add Folder with
  Subfolders…" (also the empty list's "Choose Folder…"), Remove, Clear, Sort (by name, Finder order), Move up/down,
  and "Save List…"/"Load List…" (plain text, one path per line). Hidden and non-image files are
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
- Name card: the rename pattern, then "Save to": **Next to the originals** (empty, the default)
  or a chosen folder, with a "Next to the originals" button to go back while a folder is set
  (the reference viewer's button for the browsed folder). `{folder}` in the output path stands
  for the input file's folder name.
  The safety and date options below sit in the same card.
- Rename pattern (always applied; `{name}` by default): `{name}` original name, `{n}` counter, `{n:3}` zero-padded counter, `{date}`
  date taken (YYYY-MM-DD, file date if missing). `/` and `:` become `-`. Empty pattern keeps the
  original name. The counter starts at 1 and advances only for files that succeed.
- The window shows the first output names live, without writing anything (the reference
  viewer's test-rename button).

### Per-image operations (applied in this order)

1. Crop: fixed rectangle (x, y, width, height) from a chosen corner or the centre.
2. Resize: width and/or height, longest side, shortest side, megapixels, or percentage. Options:
   keep aspect ratio (default on), don't enlarge smaller images (default on), don't shrink
   larger images, DPI value.
3. Rotate left/right, flip horizontal/vertical.
4. Colour: greyscale, negative, auto-adjust colours, brightness, contrast, gamma, saturation,
   per-channel balance, sharpen, blur, reduce colour depth. Filters, each with one strength
   value: unsharp mask, noise reduction, sepia, colour temperature, auto levels (histogram
   stretch). No artistic filters.
5. Auto-crop uniform borders, canvas size, border, text overlay, watermark image:
   - Canvas size, one of: a width per side (negative values cut into the image); a total size
     in pixels (0 keeps that side) placed at one of 9 anchors; or an aspect ratio (1:1, 2:1, 3:2,
     4:3, 16:9, 16:10, √2, or custom) at one of 9 anchors. New area in one colour (transparent
     when the output format has alpha and the colour is clear).
   - Border: one or two nested solid borders, each with a width in pixels and a colour.
   - Text: one or more lines with `{name}`, `{folder}`, `{date}` (as in Rename) and `{n}` (the
     file's place in the list: the rename counter is only known once earlier files are
     written); font from the system font panel, size as % of the image's shorter side; colour;
     one of 9 positions with a margin in % of the shorter side; in the image or on a strip added
     below or above it; opacity; optional shadow and background box.
   - Watermark: an image file (PNG with alpha works best) at one of 9 positions with a margin,
     sized as % of the output's width, with an opacity (default 33 %).

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

- Runs in parallel on all cores but one. The window shows progress (see "Window"); the log has
  one line per file (output name or error) and is copied with "Copy Log". Stop (finishes files in
  flight, starts no more) and Pause/Resume.
- A failing file never stops the batch and never leaves a partial output file.

## Preferences (⌘,)

The menu calls it "Preferences…", not macOS's "Settings…", so it matches its single key P.

A standard Mac settings window with symbol tabs in its toolbar; the window changes height to fit
each tab. Each tab is a grouped form: settings in titled groups of rounded cards, labels leading,
controls trailing, switches for on/off settings. Every setting below has the default shown.

- Browsing: past the end of a folder: folder chooser (default) / loop this folder / stop; show
  hidden files (off); after Move to Trash or move to folder, show the next image (on); move,
  copy and trash sidecar files with the same name (`.xmp`, `.aae`, `.thm`) together (on); check
  for updates automatically (on, see "Updates").
- Viewer: appearance (System; also Light, Dark), for every window of the app; checkerboard behind
  transparent images (on); remember the window's size and position (on); zoom step (10 %); hide
  toolbar and status bar while viewing (off, see "Toolbar").
- Full screen: overlay text (off; template with `{name}`, `{folder}`, `{index}`, `{count}`,
  `{size}`, `{date}`); hide the pointer (on).
- Move / copy: the 14 destination slots; ask before each move / copy (off).
- Open with: up to 3 external apps, opened with ⌥1, ⌥2, ⌥3 on the current file.
- Formats: per-format defaults (see "Format options"), saved profiles.

## About window

Our own About window replaces the plain standard panel. Mac-like, one small
window, nothing to configure.

- The feather icon, "Featherview", version and build (`0.1.0 (1)`), the one-line description.
- Links: website, source code on GitHub, report a problem (the bug report form, as Help › Report a
  Bug…), all opening the browser.
- "Supported formats": two lists, read and write, built at runtime from ImageIO plus our own
  encoders (see "Formats"), with the macOS version they come from.
- "MIT License" and "Acknowledgements": the licence text of every bundled library (libwebp, jxrlib), each
  in a scrollable sheet. Copyright line.
- Clicking the version shows a small "Copy" bubble (as a value in iOS settings does); it copies
  version, macOS version and Mac model as text, for bug reports.
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
  GIF, BMP, ICO, ICNS, JPEG 2000, PSD, TGA, OpenEXR, Radiance HDR, SGI, PBM, DDS,
  DNG and camera RAW from all major makers.
- PDF (milestone 3, like the reference viewer): a PDF is browsed like a
  multi-page image. Core Graphics renders each page on white at 144 dpi (an A4 page is
  1190 × 1684 pixels; fit mode renders it straight at the window's size), opening on page 1; ⌥← / ⌥→ step pages and the page shows in the title and status bar.
- Read, formats ImageIO can't read, which Featherview decodes itself:
  - SVG through AppKit (`NSImage` renders it; ImageIO doesn't), rasterised at the size shown.
  - Own decoders, pure Swift, no dependency (milestone 3): QOI, PCX (and multi-page DCX), XBM,
    XPM, WBMP, Sun Raster (RAS), IFF/LBM (ILBM, incl. HAM and EHB), Kodak Photo CD (PCD: the
    768 × 512 Base image, turned upright, PhotoYCC converted with reference white at 255; the
    larger 4Base and 16Base images are a known limit). Also MacPaint (with or
    without a MacBinary header), farbfeld, X Window Dump (version 7, Z pixmaps), FITS and Windows
    animated cursors (ANI). FITS shows the first image in the file (its first plane, or three planes
    as RGB); 8-bit data as stored, everything else stretched linearly between the 0.25th and 99.75th
    percentile; the first row is the bottom one; tile-compressed FITS can't be opened. ANI shows its
    first frame at its largest size (playing it: "Animation", v2). PAM goes through ImageIO, which reads it
    with the rest of the Netpbm family (PFM too).
  - JPEG XR (.jxr, also HD Photo .wdp/.hdp) through jxrlib (BSD-2-Clause, built from source, per
    `AGENTS.md`). Every pixel format is brought to 8-bit sRGB: HDR and wide-gamut files are clipped,
    an embedded colour profile is ignored, premultiplied alpha (Office's HD Photo files) is undone.
    Known limits: CMYK with alpha and n-channel files can't be opened; only the first frame shows.
  - BPG without a third-party HEVC decoder (every free one is LGPL): the header's VPS/SPS fields are
    rebuilt and the stream rewrapped as HEIF, which ImageIO decodes with the system's HEVC decoder.
    Grey, 4:2:0, 4:2:2 and 4:4:4, 8 to 10 bits, YCbCr (BT 601/709/2020), RGB and YCgCo (4:4:4),
    full or limited range, alpha (straight or premultiplied). Known limits: the first frame of an
    animation only, the ICC profile is ignored; 12 and 14 bits, CMYK, and RGB or YCgCo with
    subsampled chroma can't be opened (macOS decodes nothing); damaged picture data shows as HEVC
    conceals it, and a fully transparent black picture is taken for a failed decode.
  - Layered app formats, shown flattened (own milestone after 3): PSB (its stored composite
    image), XCF (GIMP), PDN (Paint.NET), PSP (Paint Shop Pro). Where the file stores a composite
    or thumbnail at full size it is used; otherwise visible layers are composited with normal
    blending and their opacity, and other blend modes are listed as a known limit.
    Krita (KRA) and OpenRaster (ORA) are zip archives with the flattened picture stored as
    `mergedimage.png`, which is shown; a file without one can't be opened.
    PSB goes through ImageIO, with its limits: multichannel files and a zip-compressed composite
    can't be opened, and a composite GIMP stored with premultiplied alpha shows dark antialiased
    edges (ImageIO reads it as straight alpha). CMYK and grey PSB colours go through ImageIO's
    colour management, so they differ slightly from a plain conversion.
    Procreate (`.procreate`) shows the flattened picture Procreate keeps in the file, at full size,
    in the document's colour profile, and turned and flipped the way the canvas was (as its own
    preview shows it). Its tiles are LZO1X or LZ4 compressed; LZO1X is our own decoder, LZ4 is
    macOS's. If that picture is missing or can't be read, the stored preview (at most 1024 pixels
    wide) is shown instead. Known limit: a flipped canvas is untested against a real file.
  - Every own decoder goes through the same paths as ImageIO's: folder listing by extension,
    downsampled decode at screen size, batch input, info panel (dimensions only). A file it
    can't read shows "Can't open <name>" like any other.
- Finder previews (after the own decoders): a Quick Look preview and
  thumbnail extension for the formats only Featherview reads, reusing its decoders, so Finder,
  Quick Look (Space) and open panels show them too. Formats ImageIO reads are left to macOS.
- Write (ImageIO): JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, JPEG 2000, PDF, PSD, TGA, ICO, ICNS,
  OpenEXR.
- Write (own encoders, pure Swift, no dependency): PBM, PGM, PPM, QOI, PCX. PBM is real 1-bit
  plain PBM (P1, the only PBM macOS reads), black and white at a 50% threshold (ImageIO's PBM writer writes
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
| WebP | preset photo (default) / picture / drawing / icon / text, lossless, quality 1–100 (default 75), effort 0–6 (default 4) |

After testing ImageIO on macOS 27: it can't write JPEG without chroma subsampling
(except at quality 100), lossless HEIC/AVIF, PNG compression levels or interlaced GIF, so those
options are not offered. ImageIO's GPU texture formats (KTX, KTX2, ASTC, PVR, ATX, DDS) and HEIC
sequences are not offered for writing; any other type a newer macOS adds appears automatically.

Orientation is always applied to the pixels and the tag reset to 1 (not an option). Options are
remembered per format and can be saved as named profiles.

### Animation (v2)

Animated GIF, PNG (APNG), WebP and HEIC sequences, and Windows animated cursors (ANI), play in the
viewer in a loop, with the delays the file gives. The first frame shows as fast as a still image;
the rest follow. Converting (batch, Save As, copy) uses the first frame. Details (pause, stepping
frames, frame count in the status bar) are decided in the milestone's plan.

## Not in v1

See "Out of scope for v1" in `AGENTS.md`.

## Distribution

Releases are ad-hoc signed and not notarized (no paid Apple Developer
account). README.md tells users how to open the app the first time.

The app ships in a disk image whose window shows the app, an arrow to an Applications link, and a
help box for the first open: open Featherview once, then System Settings › Privacy & Security ›
Open Anyway (since macOS 15 Control-click › Open no longer does it). Dark background in the icon's
tile colour with faint feather lines; drawn by code at 1× and 2×, no copied artwork. One disk image
for every language, built by `scripts/dmg.sh`; its help text is English (a background holds one
language), the app inside follows the Mac's language. Revisit if someone sponsors
the $99/year Apple Developer Program; then sign with Developer ID and notarize.

## Updates

Featherview tells people when a newer version exists; they download and install it by hand. It
never downloads or installs anything itself.

- Feed: `https://featherview.mynetx.net/appcast.xml`, Sparkle appcast format (RSS 2.0 with the
  `sparkle` namespace). Per `<item>`: `<title>`, `<sparkle:shortVersionString>` (e.g. 1.2.0),
  `<sparkle:version>` (build), `<sparkle:minimumSystemVersion>`, `<link>` (the release page),
  `<description>` (release notes, plain text or simple HTML), `<pubDate>`. An item without a
  version or an https link is ignored; a malformed or empty feed means no update.
- The request is a plain GET with no cookies, cache or anything about the person beyond the HTTP
  request itself; User-Agent `Featherview/<version>`; 15 s timeout.
- Versions compare numerically by dotted parts (1.10 is newer than 1.9; missing parts count as 0).
  The update offered is the newest release that is newer than the running one, runs on this
  macOS version, and is newer than a skipped version.
- Automatic check: about 10 s after launch, off the main thread, when Preferences › Browsing ›
  "Check for updates automatically" is on (default) and the last successful check is at least
  24 hours ago. Any failure is silent; it tries again at the next launch.
- Check for Updates… (app menu) ignores the schedule and the skipped version and always answers:
  the update window, or a short alert ("Featherview 1.2.0 is the newest version." / "Can't check
  for updates right now.").
- Update window: a small window of its own, not modal, in our own look: "Featherview 1.3.0 is
  available", "You have 1.2.0.", the release notes as plain text (tags stripped, scrollable), and
  Download (default; opens the release page in the browser), Skip This Version, Later.

## App icon

The feather mark, `Resources/AppIcon.svg` (source of `AppIcon.icns` and the
website favicon). No cat imagery.
