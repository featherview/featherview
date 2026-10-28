# Parity with the reference viewer

Behaviour observed black-box in the reference viewer (see "Clean-room rules" in `AGENTS.md`),
written in our own words. Not requirements: an item becomes one only when it lands in
`docs/spec.md`.

Status: `v1` (already in the spec), `later`, `won't` (with a one-line reason), `open` (undecided).

Default settings, Windows 11 ARM VM, test folder of 12 generated images in
5 formats plus a corrupt file, a text file and a hidden file. Keys below are physical keys; the VM
has a German layout, so `+`/`−` were checked on the numpad and the German `+`/`-` keys.

## Browsing

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Folder list | Opening a file lists its folder in natural order (img2 before img10), case-insensitive. | Same. | v1 |
| Folder list | Hidden files are listed and count toward the total. | Skip hidden files (Finder hides them too). | v1 |
| Folder list | Corrupt files with an image extension are listed and count toward the total. | Same: listed, shown as an error when reached. | v1 |
| Folder list | The list is refreshed on a key (F5) to pick up new files. | F5 and ⌘R (View › Refresh) rescan now, also with Follow New Files off; the current image stays, or the one at its position if it is gone. | v2 |
| Next / previous | → Space Page Down and wheel-down go to the next file; ← Backspace Page Up and wheel-up go back. | Same keys. Decided: the wheel / two-finger scroll pans, never navigates. | v1 |
| Next / previous | ↑ ↓ do not change images. ← → and ↑ ↓ scroll instead when the image is larger than the window. | Decided: arrows pan when the image is larger than the window, navigate otherwise; two-finger scroll pans. | v1 |
| First / last | Home / End jump to first / last (Ctrl variants do the same). | Same. | v1 |
| End of folder | Going past the last (or before the first) file opens a small folder browser starting at the current folder: restart this folder, go up (←), or enter a subfolder (→ / Space). Siblings are listed in plain alphabetical order (d10 before d2) with image counts filled in only once visited. Every hop takes several keys. | Decided: → past the last image jumps straight to the next folder, no dialog (spec). Open: siblings only, or also subfolders; what happens after the last sibling. | v1 (details open) |
| Random | A key shows a random file of the folder. | Image › Random Image: a random other image, never the one shown; nothing with fewer than two images; off in a slideshow and the grid; menu item only, no key. | v2 |
| Corrupt file | Reaching a corrupt file shows a modal error with the full path; after dismissing it the window is empty but → continues from that position. | Spec: inline "Can't open <name>", no modal, browsing continues. Keep ours. | v1 |

## Display

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Window size | The window resizes to each image (and grows with zoom): small images at 100 %, large images shrunk to fit the screen. The window has a minimum width; small images are centred on black. | Decided: the window stays put; only the image changes. | v1 |
| Fit default | Only images larger than the screen are shrunk; small ones stay at 100 %. | Same as spec ("never enlarges small ones"). | v1 |
| Fit modes | Many fit modes exist (to window, to width, to height, to screen, none) with a few on Shift+letter keys. | Fit (0), actual size (1), zoom to width (2) and height (3); see "Zoom modes and flip". | v2 |
| Zoom | `+` / `−` zoom in ×1.1 steps (100 → 110 → 121 %). The window grows with the zoom up to the screen size. | Decided: ×1.1 steps; window stays put. | v1 |
| Actual size | Ctrl+H shows 100 %. Digits 0–9 do nothing. | Spec: `1` actual size, `0` fit (no clash). | v1 |
| Title bar | Shows the filename and, when scaled, the displayed size in pixels. A leading `*` marks unsaved edits. | Spec: `filename — 3 / 120`. | v1 |
| Status bar | One line at the bottom, five fields left to right: pixel size with bits per pixel, position N/M, zoom %, file size / decoded memory size, file date and time. After Save As it keeps showing the source image's fields. Multi-page files add the page at the end. | Proposal (milestone 3 viewer look): an optional bottom status line with dimensions, zoom %, file size, position, date; leading-aligned, Mac typography, toggled from View. | v1 |
| Full screen | Enter (or double-click) toggles full screen: black background, image fit to the screen, a small overlay with full path and position in the top-left corner (green text, observed again: full path, then position in brackets). Esc leaves full screen. | Decided: F, Return and double-click toggle; Esc leaves. Overlay on by default with full path and position (Settings › Full Screen). | v1 |
| Full screen | A left click does nothing; a right click goes to the previous image. | Not in spec (right-click on a Mac means a context menu). | open |
| Esc in window | Esc quits the program when not in full screen (confirmed twice). | Decided: Esc never quits; ⌘Q quits. | v1 |

## Actions

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Rotate | R / L rotate the displayed image right / left instantly. Not marked as an edit; navigating away discards the rotation silently and the file is unchanged. | Spec: R / L rotate losslessly and write it to the file (EXIF orientation). Ours is a deliberate difference. | v1 |
| Lossless rotate | A separate dialog (Shift+J) does lossless JPEG rotation on files. | Covered by our R / L. | v1 |
| Flip | V / H flip vertically / horizontally. | H / V flip losslessly, written to the file like R / L. | v2 |
| Delete | Delete moves the current file to the Recycle Bin at once, with no confirmation. The deleted image stays on screen; the list shrinks; → continues with the next file. | Spec: ⌘⌫ and ⌦ move to Trash and show the next image (Mac convention, and the next image appears at once). | v1 |
| Unsaved edits | Navigating away from an edited image discards the edit with no prompt. | We don't edit pixels, so nothing to discard. | won't (no pixel editing in v1) |
| Info | I opens a modal dialog with file name, folder, compression, sizes, colours, file and memory size, list position, file date and load time. | Spec: I toggles a non-modal side panel with camera data. Consider adding load time to our log only. | v1 |
| Batch | B opens batch conversion / rename. | Spec: B and ⌘B. | v1 |
| Thumbnails | T opens a separate window: folder tree on the left, grid of thumbnails with names in natural order, orientation applied, corrupt files shown with a "not allowed" symbol, text files rendered too. | T: a thumbnail grid in the viewer window (see "Thumbnails"). | v2 |
| Slideshow | W opens slideshow setup. | W starts a slideshow of the viewer's list at once, no setup (see "Slideshow"); effects stay out of scope. | v2 |
| Open / save | O opens a file, S saves as, Ctrl+S saves in place, Shift+R reopens. | Spec: O and ⌘O; S for Save As (milestone 3). Saving in place is out of scope (no pixel edits). | v1 (open), won't (save in place) |
| File ops | F2 rename. F7 move / F8 copy open a list of up to 14 remembered destination folders, picked by a single key (1–9, then letters); missing folders are created. A copy happens silently; the image stays on screen. A move removes the file from the list but the moved image stays on screen. On a name clash it asks (replace / skip / rename, with both files' size, date and preview); overwrite and auto-number are alternatives. | Decided: F7 / F8 in v1. Ours never overwrites (" 2" suffix, no prompt) and shows the next image after a move. Open: numbered destination slots (the key speed feature) vs a single last-used folder. F2 rename is open. | v1 (details open) |
| Clipboard | Ctrl+C copies the displayed image at full resolution with orientation applied (checked: 400×800 from a tagged 800×400 JPEG). Ctrl+V pastes an image as a new document. | Decided: ⌘C copies (spec). Paste: won't (no documents). | v1 |
| Other single keys | P settings, A about, C screen capture, M minimise, G animation, U/F5 refresh, D clear display, K filter plugin (marks image as edited), X shows a marker in the status bar (meaning unclear). E, J, N, Q, Y, Z and digits do nothing. | Only navigation, rotate, info, full screen and zoom keys are in our spec. | open |

| Orientation | A JPEG with an EXIF orientation tag (6) is shown upright. | Same (spec). | v1 |
| Instances | Opening a second file from outside starts a second window; each has its own folder list. | Open: one window that switches to the new file (Mac norm), or one window per file. | open |
| Text files | A .txt file in the folder is listed and rendered as a tiny picture of its text. | Only decodable images are listed (spec). | v1 |

## Batch

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Modes | Convert, rename, or convert and rename. | Spec: convert with optional rename. Rename-only (no re-encode) is open. | open |
| Inputs | A file browser plus add, add all (skips hidden and non-image files, but includes corrupt ones), remove, remove all, sort, move up/down, save/load the list as text, optional subfolders. The list is grouped by type, not natural order. | Spec: Add Files, Use Viewer's Folder, Clear. Subfolders and list save/load: later. | v1 |
| Output folder | Default is a fixed temp folder; a button uses the browsed folder; placeholders allowed in the path. | Spec: chosen by the user. | v1 |
| Rename | Pattern with `#` as counter digits (default image###). The counter advances only on success. A test-rename button previews names. | Spec: `{name}`, `{n}`, `{n:3}`, `{date}`; the counter advances only on success, and the preview lists the first output names (milestone 4). | v1 |
| Errors | A corrupt file gets an error line in the log and the batch continues. | Same (spec). | v1 |
| Clashes | With overwrite off (default), an existing output is skipped with a warning; nothing is written for that file. | Spec: never overwrite, append " 2". Ours writes every file. | v1 |
| Orientation | Output pixels are upright and the orientation tag is reset to 1. | Same (spec). | v1 |
| Input order | Each Add appends its selection to the end of the list, the selection sorted by name; earlier entries stay where they are. Add all groups by file type (in no alphabetical order), plain alphabetical within a type (img10 before img2). A sort button offers name (plain or natural), date, size, extension or date taken, ascending or descending, or none, plus an off-by-default option to sort after every add. | Add Files… appends each selection in Finder order (v1). Use Viewer's Folder takes the viewer's Finder order instead of grouping by type. A Sort command: milestone 4. | v1 |
| Counter | The rename counter follows list order and skips failed files: the file after a failed one gets the next number, no gap. | Same since milestone 4: the counter follows list order and skips failed files, no gap. | v1 |
| Progress | A log window lists each input and its result, a summary of files and errors, and buttons to copy the log, stop, pause/resume, go back to the batch, or exit. | Spec (milestone 4): the run view shows n of N, time left, the log, Pause/Resume, Stop and Copy Log; each row shows its state; a summary line stays after the run. | v1 |
| Threads | Multithreading is optional and off by default (5 threads offered). | Spec: always parallel on all cores but one. | v1 |
| Advanced | Per-batch operations: crop; resize by width/height, long side, short side, megapixels or percent, with keep-aspect, don't-enlarge and don't-shrink switches and DPI; colour depth; flip, rotate, greyscale, negative, auto colours, auto-crop borders, canvas, text/watermark overlay, border, replace colour, channel swap; sharpen, brightness, contrast, gamma, saturation, colour balance, blur, fine rotation; misc: overwrite, delete originals, subfolders in destination, keep file date, processing order, save/load presets. | Spec (milestone 4): crop, resize (longest side, width/height, megapixels, percent, keep aspect, don't enlarge/shrink, DPI), rotate/flip, colour (greyscale, negative, auto colours, brightness, contrast, gamma, saturation, RGB, sharpen), filters, auto-crop, canvas, border, text, watermark, colour reduction, safety options and presets. Artistic effects stay out of scope. | v1 |
| Canvas size | Three ways to grow the canvas: a border width per side (negative values put it inside the image, i.e. crop), a total canvas size in pixels (0 keeps that side) with one of 9 anchors, or a target aspect ratio (1:1, 2:1, 3:2, 4:3, 16:9, 16:10, √2 or custom) with the same anchors. New area is a chosen colour, or optionally filled with a blurred (optionally flipped) copy of the image with a strength value, plus a gamma for the new area. Option to make the new colour transparent for 32-bit output. Named saved sizes. | Spec: per-side border, total size + anchor, aspect ratio + anchor; colour fill. Blurred fill and saved sizes: later. | v1 |
| Text overlay | Position as x/y offsets from one of 5 corners/centre plus a box width/height. Multi-line text with placeholders for file folder and name, and buttons that append copyright, date, time or EXIF date. Background none / semi / opaque with a colour; text opacity none / semi / transparent; effects outline (2 kinds), shadow, emboss; font and colour pickers; alignment left/centre/right; rotation −360…360°; placement in the image, or above / below it on added canvas; named profiles. No preview in batch mode. | Spec: text with `{name}`/`{date}` placeholders, system font panel + colour, corner + offset, alignment, opacity, shadow, in image or on an added strip below. Outline/emboss/rotation: later. | v1 |
| Watermark | Position as x/y offsets from one of 5 corners/centre plus a width/height box; either a chosen image (PNG with alpha recommended) or a plain colour rectangle; one opacity slider (default about a third). | Spec: image file, corner + offset, opacity, size as % of the output's width. Colour rectangle: out (that's editing). | v1 |
| Border / frame | About 17 named frame styles (plain, gradients in grey/red/green/blue, broken edges, fading, lines, inlays); up to four nested borders, each with its own width and colour; picking a style loads its default widths and colours (both switchable off). The preview area stays empty in batch mode. | Spec: one or two nested solid borders with width and colour; style presets: out. | v1 |
| More effects | A list of about 46 artistic and correction filters (blurs, emboss, oil paint, edge detection, median, pixelize, unsharp mask, red-eye, sepia, solarize, twirl, swirl, fish eye, noise, metallic, colour temperature, histogram stretch/equalise, blinds and more); each can be ticked, several at once, and the selected one shows a single strength slider. | Spec: the correction ones that Core Image has (unsharp mask, median/noise reduction, sepia, colour temperature, histogram/auto levels). Artistic effects: out (editing). | v1 |
| Batch preview image | A small thumbnail under the start button shows the file selected in the file browser or the input list, unprocessed: the batch's changes (greyscale tried) are not applied to it. It can be turned off. | Spec: thumbnail of the selected input; show it with the operations applied (live, small, off the main thread). | v1 |
| Multi-page input | A 3-page TIFF converted to JPG gives one file with the first page only; the log reports it as fine, with no warning. No setting writes one file per page; the only page setting applies the batch changes to every page when the output is TIFF or PDF. | Same: first page only into single-page formats, every page into TIFF (keep all pages) and PDF. The log line also says how many pages the file has, so nothing is dropped silently. | v1 |


## Formats and options (batch and Save As share the same option dialogs)

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Input formats | The open dialog lists, besides audio and video: ANI/CUR, B3D, BMP/DIB/RLE, CAM, CDR/CMX (preview only), CLP, CPT, camera RAW (CRW/CR2/CR3, DCR, DNG, EFF, MRW, NEF, NRW, ORF, PEF, RAF, SRF, ARW, RWL, RW2, MPO, 3FR, IIQ, MOS, KDC), DICOM/ACR/IMA, DDS/BLP, DjVu, DPX/CIN, CAD (DWG, DXF, HPGL, CGM, SVG, PLT), ECW, PDF/EPS/PS/AI, icons in EXE/DLL/CPL, EXR, FLIF, FPX, G3 fax, JPEG XR (HDP/JXR/WDP), HEIC/AVIF, ICO, IFF/LBM, GEM IMG, JPEG-LS, JPEG 2000, JPEG, JPM, JPEG XL, MNG/JNG, PBM/PGM/PPM, PCD, PCX/DCX, PDN, PNG, PSD/PSB, PSP, QOI, Sun RAS, raw YUV, Utah RLE, SFF, SFW, SGI, MrSID, SWF/FLV, TGA, TIFF, TTF fonts, WBMP, WBZ/WBC, WebP, WMF/EMF, WSQ, XBM/XPM, XCF. (open dialog's type list, with the viewer's official plugins pack installed, as a typical user has it). | macOS 27 ImageIO reads 62 types (all of the RAW list but KDC, plus PSD, EXR, DDS, DICOM, HEIC/AVIF, WebP, JPEG XL, PBM family, SGI, TGA, ICO/CUR, PICT, Radiance HDR, ICNS, KTX/ASTC/PVR); AppKit also renders SVG. Not readable on macOS: QOI, PCX/DCX, XCF, PSB, PSP, PDN, JPEG XR, JPEG-LS, JPM, FLIF, DjVu, DPX/CIN, WMF/EMF, IFF/LBM, Sun RAS, XBM/XPM, WBMP, MNG, PCD, ANI and the rest. Decided: SVG via AppKit and own decoders for QOI, PCX/DCX, XBM, XPM, WBMP, RAS, IFF/LBM (milestone 3), flattened XCF, PSB, PDN, PSP (milestone 7), Finder previews for them (milestone 8). The rest: not planned. | v1 |
| PDF input | With the bundled PDF plugin enabled, a PDF opens like an image and is browsed among the folder's images: page 1 rendered on white at 96 dpi (an A4 page shows as 793×1123), the page as "n / m" at the end of the status bar, Ctrl+Page Down / Up step pages like a multi-page TIFF. | shown, pages like a multi-page TIFF, rendered by Core Graphics (spec "Formats"). | v1 |
| Output formats | 20 output formats: BMP, ECW, EMF, GIF, ICO, JLS, JPEG 2000, JPEG, JPEG XL, PCX, PBM, PDF, PGM, PNG, PPM, QOI, RAW, TGA, TIFF, WebP. No HEIC. | ImageIO formats + own PGM/PPM/QOI/PCX + WebP via libwebp; JPEG XL via libjxl (v2); HEIC and AVIF beyond the reference. | v1, JPEG XL v2 |
| JPEG options | Quality (default 80), progressive, no chroma subsampling, keep EXIF/IPTC/XMP/comment (on), reset orientation (on), reuse original quality, target file size, profiles. | Spec "Format options". | v1 |
| PNG options | Compression level 0–9 (default 6), custom transparent colour, optional extra optimiser. | Spec (effort levels). | v1 |
| TIFF options | None / LZW / PackBits / JPEG / ZIP, three bilevel codecs, keep all pages, greyscale palette. | Spec (bilevel codecs: later). | v1 |
| WebP options | Preset (default/photo/picture/drawing/icon/text), lossless or quality (default 75), method 0–6 (default 4), passes, filter strength, sharpness. | Spec (passes / filter / sharpness: later). | v1 |
| Save As dialog | The save panel has a format list, a recent-folders list, "keep the original file date" (off) and "show options" (on). The chosen format's options sit in a separate small panel beside the save panel and change with the format; that panel opens from a button, and batch reaches the same options through a button next to the format. The last format is remembered. After saving, the window's title switches to the new file. | ⇧⌘S: NSSavePanel with a format pop-up and an Options… button in its accessory view that shows the format's options in a sheet (spec "Output"); remember format and options. the window switches to the saved file, like the reference. | v1 |
| GIF options | Interlaced (off); custom transparent colour (off) taken from the window background, picked while saving, or a palette index. A 24-bit image is reduced to 256 colours without asking. | ImageIO GIF: no interlace or palette control; offer no options in v1, reduce colours silently. | v1 |
| JPEG 2000 options | Lossless (default), or quality 1–100 (default 90), or a target size in bytes. | ImageIO JPEG 2000: lossless vs quality slider; target size by the same binary search as JPEG. | v1 |
| TGA options | None. Writes uncompressed (36 MB for 4000×3000 24-bit). | Same: no options. | v1 |
| PDF options | Save all pages (on); page size like the image (default) or A4/A3/A2/A1/A0/Letter/Legal/Ledger with portrait/landscape; for a paper size, image size (original by DPI, fit to page (default), stretch) and position (centre or a corner/edge, 7 choices); author; compression for colour and grey images (none, lossless, JPEG 95 (default)/80/65/40) and for black-and-white (none, lossless (default)). | PDF via Core Graphics: page like the image or a paper size, fit/actual, centred; JPEG quality for photos. Author and positions: later. | v1 |
| Rename options | Old-name placeholder and `#` digits; start and step for the counter; remember last counter; three find/replace pairs; rename-only mode copies, moves or renames in place; clash: error / numbered duplicate / overwrite; profiles. | Spec: placeholders, counter, preview, presets. Open: counter start/step, find/replace, rename in place. | open |

## Preferences (P)

16 pages. Relevant behaviour: start folder, single instance (off), start in full screen, warning on Esc-quit (off), auto-rotate by EXIF (on), play animated GIFs (on), file types browsed, transparency checkerboard (on), dark mode (off), remember window frame (on), background colour, status-bar template; browsing: end-of-folder = browser / loop / stop, show hidden files (on), wheel navigates only without scrollbars; full screen: 7 fit modes on digits 1–7, centring on C, overlay text template, hide cursor; zoom step 10 % (relative/absolute/table); colour management off (plugin); file handling: default copy/move folders, confirm delete, jump to next after delete/move (off), sidecar files (THM/XMP) moved along (off), save/overwrite prompts; misc: recent files and folders, 3 external editors, any unused key ends full screen. Featherview: see spec "Settings" (Mac-style, our defaults differ where noted).

## Opening

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Drag and drop | Dropping a file on the window opens it and lists its folder (subfolders not included). | Same (spec). | v1 |
| Folder | Opening a folder (as the program's argument) shows the first entry of its list, even a hidden file; a folder whose only file is a text file shows that file rendered as a picture. | Spec: starts at its first image, hidden files skipped. Open: what an imageless folder shows (suggest "No images in <folder>", ← / → still move to other folders). | v1 |

## Mouse, pages and toolbar

On a 4000×3000 JPEG and a 3-page TIFF, default settings.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Left drag | Draws a selection rectangle, in any direction, fitted or zoomed in; the title shows its origin and size in image pixels. It never pans. A plain click clears it. The selection survives a zoom change. | Selection only serves editing (crop, copy part): out of scope. Suggest: dragging pans a zoomed image (the Mac norm, like Preview's move tool), does nothing when it fits. | v1 |
| Right drag | Pans a zoomed image, grab style (the image follows the pointer). | Mac: plain drag pans (row above); right-click is for a context menu. | v1 |
| Right click | In a window, a right click without dragging shows nothing (no menu, not even with the menu key). In full screen it goes to the previous image (see Display). | Suggest a context menu with the window's actions (copy, rotate, move / copy to, Move to Trash, Show in Finder, Open With), as Mac apps do. | v1 |
| Middle click | Nothing visible. | Nothing. | won't (no behaviour to match) |
| Multi-page | A multi-page TIFF opens on page 1. Ctrl+Page Down / Ctrl+Page Up go to the next / previous page; at the last page nothing happens. The page shows as "n / m" at the end of the status bar; the title doesn't change. Plain Space / Page Down leave the file for the next one; coming back starts on page 1 again. | Not in spec (spec reads the first frame). Suggest: ⌥→ / ⌥← (Mac keyboards often lack Page keys) step pages, title `name — page 2 / 3 — 3 / 120` only for multi-page files, always start at page 1. | v1 |
| Toolbar | A row of small buttons under the menu: open, slideshow, save as, print, delete, cut, copy, paste, undo, info, a zoom-level dropdown, zoom in, zoom out, previous file, next file, previous page, next page (greyed out unless the file has pages), settings, help. Tooltips name the function. | Spec "Toolbar" (decided). Candidates to add: a zoom-level menu, page buttons for multi-page files. Skip slideshow, print, cut / paste / undo (out of scope). | open |

## Layered app formats

Our own sample files (Paint.NET, GIMP and PaintShop Pro files from open-licence projects, plus
GIMP-generated XCFs), opened with the viewer's PDN and XCF plugins enabled by hand (both ship
switched off with a warning that they are old; until then opening such a file shows a decode error).

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| PDN | Opens at the full canvas size (800 × 600, 694 × 424), not the small thumbnail in the file. Page 1 is the flattened image, matching Paint.NET's own thumbnail including layers with other blend modes; pages 2 … n are the layers one by one, bottom layer first ("1 / 15" for 14 layers). The status bar says 24 bits per pixel. | Spec: flattened image only; layers are not shown as extra pages. | v1 |
| XCF | Opens flattened at the canvas size, hidden layers left out. A Multiply layer looks applied; a layer group set to Screen is drawn as if Normal. No pages. | Spec: visible layers, normal blending with opacity, other modes a known limit. | v1 |
| PSP | A one-layer file whose only stored composite is a 300 × 225 thumbnail opens at the full 800 × 600 from its layer. No pages. | Spec: full-size composite when stored, else the layers. | v1 |

## Animation

Own animated GIFs (6 frames at 0.5 s looping forever, 3 frames at 1 s with a loop count of 1, a
zero-delay one), default settings.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Playing | An animated GIF plays as soon as it opens, at the delays in the file, in a loop. | Same (spec "Animation"). | v2 |
| Loop count | A file asking to loop only once kept looping. | Same: always loops. | v2 |
| Zero delay | Frames with no delay play at a moderate pace, not as fast as possible. | Delays of 10 ms or less count as 100 ms, as browsers do. | v2 |
| Pause | G stops the animation on the frame shown and starts it again from there; the Options menu has the same command. | G, and Image › Pause / Play Animation. | v2 |
| Frames | Ctrl+Page Down / Up step one frame while stopped. | ⌥→ / ⌥← step frames (pages' keys, stopping playback), nothing past either end. | v2 |
| Status bar | The last field shows the number of frames; it doesn't change while playing or stepping. The title shows no frame. | The frame count while playing; "frame 3 / 6" while paused; title unchanged. | v2 |
| Next file | Moving on from a stopped animation to another one plays the new one; pause isn't remembered. | Same; coming back starts again at frame 1. | v2 |

## Thumbnails

Own folder of 60 generated JPEG/PNG/BMP images of random sizes and dates, plus a corrupt file, a
text file, an EXIF-rotated JPEG and a subfolder; default settings.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Opening | T opens a separate window on the current image's folder, with the current image selected and scrolled into view. T again later reopens it, selection following the image shown in the viewer. The title gives the number of files. | T (also ⇧⌘T and a toolbar button) turns the viewer window into a grid of its list, on the current image, selected and centred; T again, Return or double-click go back on the focused cell, Esc to the image shown before. Title: folder name and image count. | v2 |
| Layout | Folder tree on the leading side (shortcuts for the user's folders, then drives), path field above, grid on the rest. Subfolders show only in the tree, not in the grid. Each cell is a square of fixed size (100 pixels by default, a setting) with the image scaled to fit inside, aspect kept, small images not enlarged, file name below. | Grid only, no folder tree (Finder and the folder chooser choose folders); square cells of 64–256 pt from a slider in the status strip (default 128, remembered), the image fitted, never enlarged, name below. | v2 |
| Contents | Same files and natural order as the viewer's list: the text file and the corrupt file get cells too (corrupt one a "can't open" symbol), the EXIF-rotated image upright. | Same list and order as the viewer; unreadable files get a can't-open symbol; orientation applied; thumbnails decoded off the main thread at cell size, never blocking. | v2 |
| Hover | Hovering a cell shows a tip with path, position in the list, pixel size, bit depth, file size and date. | A tooltip with the name, then pixel size, file size, position ("3 / 120") and date, read when the pointer arrives; "Can't open <name>" for a file that can't be opened. | v2 |
| Keys | Arrow keys move the selection in the grid. Return opens the selected image in the viewer and brings it to front. Esc closes the thumbnail window, leaving the viewer on its image. | Arrows, Home / End move the selection; T, Return or double-click show the focused image in the viewer; Esc goes back to the image shown before. | v2 |
| Selection | Click selects, Shift-click a range, Ctrl-click adds or removes one; select all exists. | Click, ⇧-click, ⌘-click, ⇧-arrows, ⌘A. | v2 |
| Actions | On the selection: move, copy, delete (to the bin), batch conversion with the selected files (B), and many export and print commands. Also: drop selected thumbs from the list, refresh, sort (by name and other keys), views other than the grid (tiles, details, list), load all subfolders. | Space Quick Look, ⌦ / ⌘⌫ Trash, F7 / F8, B (batch with the selection), Adjust Date Taken…, F5 refresh; View › Sort By applies. Other views and exports: not planned. | v2 |

## Viewer conveniences

Own folder of 1600 × 900 JPEGs (c1 … c6) plus a 900 × 3000 and a 4000 × 700 one, default settings.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Recent files | A submenu of the last 15 files with full paths, newest first, plus a command that clears it. Every image shown goes in, not only opened ones: browsing with the arrow keys, a slideshow and automatic viewing all add their images. A renamed file keeps its old entry; choosing an entry whose file is gone shows a modal warning and drops that entry. A second submenu lists recently saved files (empty here). | File › Open Recent: the system's recent documents, newest first, then Clear Menu; files and folders opened (⌘O, drop, Finder, Save As), not browsed images; gone or trashed files left out. The Dock menu shows macOS's own copy of the list. | v2 |
| Rename | F2 opens a small dialog: the name without extension, preselected, a separate extension field, and an off-by-default option to rename same-named sidecar files too. A name that exists already gives a modal error naming the target path; nothing is overwritten. After a rename the title shows the new name and the list re-sorts: the file moved from 3/6 to 6/6 and → then hit the end of the folder. | F2, File › Rename… or a click on the title's name: rename in the window title as Preview does (a sheet with the toolbar hidden or in full screen); a taken name says so and nothing is overwritten; a changed extension asks first; sidecars follow; the list re-sorts and the image keeps its place on screen. | v2 |
| Sort | A submenu sorts the viewer's list by name (plain or natural, natural ticked by default), date, date taken (marked as slower), size, extension or not at all, with a separate descending toggle. Changing it keeps the current image on screen and updates its position (20/63 became 33/63 for date). Date sorts oldest first. | View › Sort By: Name (Finder order), Date Modified, Date Taken, Size, Kind, Ascending / Descending; one order for every window, remembered; the current image stays; Date Taken re-sorts once the dates are read, after the first image shows. | v2 |
| Paste | Ctrl+V shows the clipboard image as an unsaved image named after the date with a counter, marked unsaved in the title; the status bar shows no position, file size or date. → leaves it with no prompt and the paste is gone; the list continues from where it was before the paste. | File › New from Clipboard (⌘N) shows it as an unsaved "Untitled" image over the list, which Save As writes; leaving it asks first (Save… / Don't Save / Cancel), as Preview does. | v2 |
| Desktop picture | A submenu sets the current image as the desktop picture: centred, fill, tiled, stretched, stretched in proportion, or spanned over all screens, plus a command to go back to the previous one (Ctrl+Shift+letter shortcuts). Not tried, only the menu read. | Set as Desktop Picture submenu: Fill Screen (default), Fit to Screen, Stretch to Fill Screen, Center; every screen, black around Fit and Center. | v2 |
| On top | A toggle keeps the window above other windows. | Window › Float on Top, per window, not remembered. | v2 |
| Share / e-mail | No share command; only e-mailing the file through a plugin (not tried). | Share in the toolbar, the File menu and the context menu: the system's share picker (covers Mail). | v2 |

## Zoom modes and flip

Same folder, window maximised.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Fit modes | A submenu lists 12 mutually exclusive fit modes: window to image, image to window (all or only big ones), to window width, to window height, small side to window, the same five against the desktop, and none; the default is only big images to the desktop. A fit mode applies to every image after it until changed. | Zoom to Fit (0), Actual Size (1), Zoom to Width (2), Zoom to Height (3); the fit mode is remembered and applies to every new image; the window stays put, so "desktop" variants aren't needed. | v2 |
| Fit width / height | Fit to width fills the window's width, small images enlarged too (a 900-wide image at 277 %); a tall image starts at its top with a vertical scroll bar. Fit to height does the same for a wide image, starting at its left edge. | Same: fill that side of the fit area, small images enlarged too; start at the top (width) or the leading edge (height; the right edge in Arabic and Hebrew). | v2 |
| Lock zoom | A toggle (Shift+L) keeps the zoom from image to image. It keeps the zoom it had when switched on: zooming further and moving on went back to that earlier value. Alone it doesn't keep the scroll position; each new image starts at its top-left corner. | View › Keep Zoom (⇧L), off by default, remembered, following the current zoom (not a snapshot taken when switched on). | v2 |
| Lock scroll | A second toggle (Ctrl+Shift+K) keeps the scroll position too: with both on, an image scrolled to its bottom-right showed the next one at its bottom-right. | Keep Zoom keeps the relative scroll position as well, one command. | v2 |
| Flip | H mirrors left–right, V upside down, instantly. The title shows no unsaved mark, moving on asks nothing and discards the flip; coming back shows the file unchanged. Same as rotate. | H / V (Image menu, context menu, optional toolbar items) flip at once and write the file through the orientation tag, losslessly, like R / L (JPEG, HEIC, TIFF). | v2 |

## Slideshow

Own 8 images, default settings unless named.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Start | W opens a large setup dialog with its own file list (empty, with a file browser starting at the drive root) instead of using the viewer's list; Ctrl+W starts at once with the viewer's list from the current image. The setup's list is kept between runs in the same session. | W (and ⇧⌘F, View › Start Slideshow) plays the viewer's list in full screen from the current image; no separate list or setup dialog. | v2 |
| Options | Advance after an interval (default 5 s) or on a key / click, in order or at random; start index; loop (off by default); remember the last index; hide errors (on); hide the cursor (off); a text overlay template (folder, name, index by default); full screen (default) or a window of a set size; close the app after the last image; export as video, a self-running program or a disc; load / save the list as text. | View › Slideshow Options: interval 1–60 s (default 5 s), Shuffle and Repeat (both off), remembered; unreadable files skipped silently; the pointer follows "Hide the pointer". Nothing else. | v2 |
| Playing | Full screen, black, each image fitted, with the overlay text (full path and "[n/m]") in green at the top-left. → / ← step at once and the timer carries on; Space steps forward too. No pause key was found. | System full screen with the usual overlay; → / ← step in play order, Space pauses and resumes, a control capsule shows when the pointer moves; Esc ends. | v2 |
| Random | Random order picks at random each time: in about a dozen picks some images came twice while others hadn't shown yet. The overlay shows the picked image's list position. | Shuffle plays every image once in a random order before repeating; the overlay shows the image's Finder position. | v2 |
| End | Without loop it stops on the last image and stays in full screen; → does nothing there. Esc ends it and leaves the window empty (no image loaded) and restored to a smaller size, not on the image that was showing. | Repeat off: stays on the last image (→ does nothing, Space plays again); Esc goes back to the window on the image shown. | v2 |
| Automatic viewing | Shift+A steps the window through the viewer's list at the slideshow interval, without full screen; after the last image it wraps to the first. → steps at once and it keeps going; Shift+A again stops it. | ⇧A (View › Play in Window): same toggle, stops at the end unless Repeat is on. | v2 |

## Compare images

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Opening | A command in the File menu opens a separate resizable window with two panes: the current image on the left, the right one empty until a file is chosen through an open panel. Exactly two images, no more. | Two images side by side in the viewer window itself: File › Compare With… (⌥⌘O, open panel) or Image › Compare on two thumbnails in the grid; the current image in the leading pane. | v2 |
| Zoom and scroll | Each pane has its own zoom list (fit, 10 – 500 %); Ctrl+wheel zooms, the wheel scrolls, right-drag pans. Zoom lock and scroll lock are separate toggles, both off by default; with both on, the two panes zoom (checked at 10 % and 200 %) and scroll in step. | One toggle, View › Zoom and Pan in Step, on by default: the same detail stays at the same place in both panes, also for images of different sizes. Off, each pane zooms and pans on its own. | v2 |
| Stepping | Buttons step the left pane through its folder (next / previous); the zoom stays and the main window follows the left pane's image (it showed c7 after closing). Another button swaps the panes. | ← / → step the first pane through the viewer's list, zoom kept; the second stays. X (or the strip's button) swaps the images; the window stays on the first pane's image after leaving. | v2 |
| Difference | A toggle shows the per-pixel difference of the two images in the right pane, with per-channel (R, G, B) switches. | D shows the per-channel difference in the second pane, all channels together, no switches. | v2 |

## Batch extras

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Extract frames | For an animated or multi-page file (greyed out otherwise): all frames or a range, a suffix with a counter (default "_page_" plus four digits, appended to the file's name: loop6_page_0001 …), a destination (default the user's temp folder) and an output format with its options (default JPEG). Each frame is written at the full canvas size. No message when done. Running it again overwrites the earlier files without asking. | A batch step, Frames and Pages: every frame or page of each input becomes its own file in the batch's format and folder, all frames, named with `{part}` (`loop-01.png` …); never overwrites (" 2" suffix rule). | v2 |
| Split into tiles | Columns × rows (default 2 × 2, more than one tile), an overlap in pixels (may be negative), destination (temp folder by default), format, all pages of a multi-page file, a right-to-left order switch. A note says existing tiles get overwritten. A 1600 × 900 image gave four 800 × 450 tiles named by row and column (c1_1x1, c1_1x2 …); a modal confirms success. | A batch step, Tiles: columns and rows (1–100, default 2 × 2), overlap in pixels (negative leaves gaps), tiles of equal size; names with row and column (`c1-1-2`); never overwrites; the preview shows the cuts. | v2 |
| Date taken | A plugin dialog for JPEG only: set the date taken to a date and time, or shift it by days, hours, minutes and seconds; for several files (from the thumbnail window's selection) add a number of seconds per file; copy the new date to the file's date (on by default). A JPEG without EXIF can't be changed (start greyed out); a separate command creates EXIF data first. | Image › Adjust Date Taken… as Photos does, in place and losslessly, for the viewer's image or the grid's selection (the others shift by the same amount); JPEG, HEIC, TIFF and PSD; the file's dates follow. In batch, a Date Taken step sets or shifts the outputs' date. A file without EXIF gains it. | v2 |
| Watched folder | Not a batch: it watches one folder (C:\TEMP by default, optionally its subfolders) and shows each new file in the viewer as it arrives, optionally clearing the display after some seconds or inverting the image. Starting it clears the window and minimises it; a new file loads without raising the window and joins the list (1/1, then 2/2). Opening the dialog again and cancelling stops the watching. | Not this: a Shortcuts action (and Finder Quick Action) that runs a batch preset on files covers automation (roadmap). Showing arriving files isn't planned; refreshing the viewer's own folder is covered under Browsing. | open |

## Metadata (info, EXIF, IPTC, histogram)

Observed on a generated 3000 × 2000 JPEG carrying camera, exposure, GPS (with altitude and image
direction), EXIF artist/copyright/description, IPTC keywords and XMP title/rating.

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| File facts | The I dialog also gives the full path, the JPEG quality it estimates and whether chroma subsampling is used, the DPI with a field to change it, the print size that DPI implies, megapixels and aspect ratio next to the pixel size, bits per pixel, a count of distinct colours, memory size, list position, file date and the time the decode took. | Info panel: header with format, dimensions and file size; Image group with megapixels, colour profile, bit depth, HDR headroom; File group with folder, dates and Show in Finder. Estimated JPEG quality and aspect ratio aren't in the spec (open); DPI change and print size: out (no printing). Load time stays in our log. | v2 (quality, aspect open) |
| EXIF view | A button in the I dialog opens a second dialog listing every EXIF tag by its raw tag name with a value, in file order, GPS tags in their own block below (coordinates in degrees-minutes-seconds plus decimal, altitude, direction). Internal entries such as IFD offsets appear too. Lines can be copied to the clipboard; a menu filters which tags are shown. | The panel shows the useful fields with readable labels; "Show all metadata…" (⌥⌘I) opens a window with every tag grouped by source, readable name plus raw tag, search, copy of selected rows or all; internal entries hidden and counted. | v2 |
| Map | No map inside the app. Buttons and a menu send the coordinate to web map services in the browser (several providers, one per item, with keyboard shortcuts), plus a satellite-view toggle. Nothing loads until one is chosen. | "Open in Maps" in the Location group (no network until clicked), plus an offline place name from data shipped in the app. No map inside the panel. | v2 |
| IPTC / XMP | A separate button opens an IPTC editor with tabs: description fields (title, author, copyright, caption, headline), keywords and categories, credits and origin, a raw XMP tag list, and options to write the same data in batch. It writes to the file. Fields the file only has in EXIF (artist, description) stay empty there; XMP title and rating show only in the raw XMP list. | Description group: title, caption, keywords, rating, creator and copyright read only, merged from EXIF, IPTC and XMP. Editing these fields isn't in the spec (only Adjust Date Taken edits metadata); decide separately. | v2 (editing open) |
| Comment | A third button shows the JPEG comment. | The JPEG/PNG comment is a row of the Description group when present. | v2 |
| Histogram | Shift+H opens a small floating window: a histogram with gray/red/green/blue channel toggles and a curves overlay, plus per-channel pixel counts at a chosen level and per-channel averages. | A histogram at the top of the info panel, luminance or RGB, with clip marks, from the already decoded picture (no extra decode); HDR to its headroom. No curves, levels readout or averages. | v2 |

## Not checked yet

the meaning of X, options of
the remaining output formats, the replace-colour and processing-order dialogs, speed on a 10,000-file
folder.
