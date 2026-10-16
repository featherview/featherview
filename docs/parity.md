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
| Folder list | The list is refreshed on a key (F5) to pick up new files. | Refresh automatically when the folder changes; no key needed. | open |
| Next / previous | → Space Page Down and wheel-down go to the next file; ← Backspace Page Up and wheel-up go back. | Same keys. Decided: the wheel / two-finger scroll pans, never navigates. | v1 |
| Next / previous | ↑ ↓ do not change images. ← → and ↑ ↓ scroll instead when the image is larger than the window. | Decided: arrows pan when the image is larger than the window, navigate otherwise; two-finger scroll pans. | v1 |
| First / last | Home / End jump to first / last (Ctrl variants do the same). | Same. | v1 |
| End of folder | Going past the last (or before the first) file opens a small folder browser starting at the current folder: restart this folder, go up (←), or enter a subfolder (→ / Space). Siblings are listed in plain alphabetical order (d10 before d2) with image counts filled in only once visited. Every hop takes several keys. | Decided: → past the last image jumps straight to the next folder, no dialog (spec). Open: siblings only, or also subfolders; what happens after the last sibling. | v1 (details open) |
| Random | A key shows a random file of the folder. | Not in spec. | open |
| Corrupt file | Reaching a corrupt file shows a modal error with the full path; after dismissing it the window is empty but → continues from that position. | Spec: inline "Can't open <name>", no modal, browsing continues. Keep ours. | v1 |

## Display

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Window size | The window resizes to each image (and grows with zoom): small images at 100 %, large images shrunk to fit the screen. The window has a minimum width; small images are centred on black. | Decided: the window stays put; only the image changes. | v1 |
| Fit default | Only images larger than the screen are shrunk; small ones stay at 100 %. | Same as spec ("never enlarges small ones"). | v1 |
| Fit modes | Many fit modes exist (to window, to width, to height, to screen, none) with a few on Shift+letter keys. | Spec has fit (0) and actual size (1) only. | later |
| Zoom | `+` / `−` zoom in ×1.1 steps (100 → 110 → 121 %). The window grows with the zoom up to the screen size. | Decided: ×1.1 steps; window stays put. | v1 |
| Actual size | Ctrl+H shows 100 %. Digits 0–9 do nothing. | Spec: `1` actual size, `0` fit (no clash). | v1 |
| Title bar | Shows the filename and, when scaled, the displayed size in pixels. A leading `*` marks unsaved edits. | Spec: `filename — 3 / 120`. | v1 |
| Status bar | One line at the bottom, five fields left to right: pixel size with bits per pixel, position N/M, zoom %, file size / decoded memory size, file date and time. After Save As it keeps showing the source image's fields. Multi-page files add the page at the end. | Proposal (milestone 3 viewer look): an optional bottom status line with dimensions, zoom %, file size, position, date; leading-aligned, Mac typography, toggled from View. | v1 |
| Full screen | Enter (or double-click) toggles full screen: black background, image fit to the screen, a small overlay with full path and position in the corner. Esc leaves full screen. | Decided: F, Return and double-click toggle; Esc leaves. Position overlay still open. | v1 |
| Full screen | A left click does nothing; a right click goes to the previous image. | Not in spec (right-click on a Mac means a context menu). | open |
| Esc in window | Esc quits the program when not in full screen (confirmed twice). | Decided: Esc never quits; ⌘Q quits. | v1 |

## Actions

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Rotate | R / L rotate the displayed image right / left instantly. Not marked as an edit; navigating away discards the rotation silently and the file is unchanged. | Spec: R / L rotate losslessly and write it to the file (EXIF orientation). Ours is a deliberate difference. | v1 |
| Lossless rotate | A separate dialog (Shift+J) does lossless JPEG rotation on files. | Covered by our R / L. | v1 |
| Flip | V / H flip vertically / horizontally. | Not in spec (editing). | later |
| Delete | Delete moves the current file to the Recycle Bin at once, with no confirmation. The deleted image stays on screen; the list shrinks; → continues with the next file. | Spec: ⌘⌫ and ⌦ move to Trash and show the next image (Mac convention, and the next image appears at once). | v1 |
| Unsaved edits | Navigating away from an edited image discards the edit with no prompt. | We don't edit pixels, so nothing to discard. | won't (no pixel editing in v1) |
| Info | I opens a modal dialog with file name, folder, compression, sizes, colours, file and memory size, list position, file date and load time. | Spec: I toggles a non-modal side panel with camera data. Consider adding load time to our log only. | v1 |
| Batch | B opens batch conversion / rename. | Spec: B and ⌘B. | v1 |
| Thumbnails | T opens a separate window: folder tree on the left, grid of thumbnails with names in natural order, orientation applied, corrupt files shown with a "not allowed" symbol, text files rendered too. | Not in spec. | later |
| Slideshow | W opens slideshow setup. | Out of scope (slideshows). | won't (out of scope) |
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
| Rename | Pattern with `#` as counter digits (default image###). The counter advances only on success. A test-rename button previews names. | Spec: `{name}`, `{n}`, `{n:3}`. Counter-on-success and a rename preview are open. | open |
| Errors | A corrupt file gets an error line in the log and the batch continues. | Same (spec). | v1 |
| Clashes | With overwrite off (default), an existing output is skipped with a warning; nothing is written for that file. | Spec: never overwrite, append " 2". Ours writes every file. | v1 |
| Orientation | Output pixels are upright and the orientation tag is reset to 1. | Same (spec). | v1 |
| Input order | Each Add appends its selection to the end of the list, the selection sorted by name; earlier entries stay where they are. Add all groups by file type (in no alphabetical order), plain alphabetical within a type (img10 before img2). A sort button offers name (plain or natural), date, size, extension or date taken, ascending or descending, or none, plus an off-by-default option to sort after every add. | Add Files… appends each selection in Finder order (v1). Use Viewer's Folder takes the viewer's Finder order instead of grouping by type. A Sort command: milestone 4. | v1 |
| Counter | The rename counter follows list order and skips failed files: the file after a failed one gets the next number, no gap. | Same, milestone 4 ("counter advances only on success"). Milestone 1 leaves a gap. | later |
| Progress | A log window lists each input and its result, a summary of files and errors, and buttons to copy the log, stop, pause/resume, go back to the batch, or exit. | Spec: progress, "N converted, M failed", one line per failure. Stop and copy-log are open. | open |
| Threads | Multithreading is optional and off by default (5 threads offered). | Spec: always parallel on all cores but one. | v1 |
| Advanced | Per-batch operations: crop; resize by width/height, long side, short side, megapixels or percent, with keep-aspect, don't-enlarge and don't-shrink switches and DPI; colour depth; flip, rotate, greyscale, negative, auto colours, auto-crop borders, canvas, text/watermark overlay, border, replace colour, channel swap; sharpen, brightness, contrast, gamma, saturation, colour balance, blur, fine rotation; misc: overwrite, delete originals, subfolders in destination, keep file date, processing order, save/load presets. | Spec: limit longest side, never upscale. Candidates: percent resize, rotate/flip, greyscale, keep file date, presets. Rest is editing: out of scope. | open |
| Multi-page input | A 3-page TIFF converted to JPG gives one file with the first page only; the log reports it as fine, with no warning. No setting writes one file per page; the only page setting applies the batch changes to every page when the output is TIFF or PDF. | Same: first page only into single-page formats, every page into TIFF (keep all pages) and PDF. The log line also says how many pages the file has, so nothing is dropped silently. | v1 |


## Formats and options (batch and Save As share the same option dialogs)

| Area | Observed behaviour | Featherview | Status |
|---|---|---|---|
| Input formats | The open dialog lists, besides audio and video: ANI/CUR, B3D, BMP/DIB/RLE, CAM, CDR/CMX (preview only), CLP, CPT, camera RAW (CRW/CR2/CR3, DCR, DNG, EFF, MRW, NEF, NRW, ORF, PEF, RAF, SRF, ARW, RWL, RW2, MPO, 3FR, IIQ, MOS, KDC), DICOM/ACR/IMA, DDS/BLP, DjVu, DPX/CIN, CAD (DWG, DXF, HPGL, CGM, SVG, PLT), ECW, PDF/EPS/PS/AI, icons in EXE/DLL/CPL, EXR, FLIF, FPX, G3 fax, JPEG XR (HDP/JXR/WDP), HEIC/AVIF, ICO, IFF/LBM, GEM IMG, JPEG-LS, JPEG 2000, JPEG, JPM, JPEG XL, MNG/JNG, PBM/PGM/PPM, PCD, PCX/DCX, PDN, PNG, PSD/PSB, PSP, QOI, Sun RAS, raw YUV, Utah RLE, SFF, SFW, SGI, MrSID, SWF/FLV, TGA, TIFF, TTF fonts, WBMP, WBZ/WBC, WebP, WMF/EMF, WSQ, XBM/XPM, XCF. (open dialog's type list, with the viewer's official plugins pack installed, as a typical user has it). | macOS 27 ImageIO reads 62 types (all of the RAW list but KDC, plus PSD, EXR, DDS, DICOM, HEIC/AVIF, WebP, JPEG XL, PBM family, SGI, TGA, ICO/CUR, PICT, Radiance HDR, ICNS, KTX/ASTC/PVR); AppKit also renders SVG. Not readable on macOS: QOI, PCX/DCX, XCF, PSB, PSP, PDN, JPEG XR, JPEG-LS, JPM, FLIF, DjVu, DPX/CIN, WMF/EMF, IFF/LBM, Sun RAS, XBM/XPM, WBMP, MNG, PCD, ANI and the rest. Decided: SVG via AppKit and own decoders for QOI, PCX/DCX, XBM, XPM, WBMP, RAS, IFF/LBM (milestone 3), flattened XCF, PSB, PDN, PSP (milestone 7), Finder previews for them (milestone 8). The rest: not planned. | v1 |
| PDF input | With the bundled PDF plugin enabled, a PDF opens like an image and is browsed among the folder's images: page 1 rendered on white at 96 dpi (an A4 page shows as 793×1123), the page as "n / m" at the end of the status bar, Ctrl+Page Down / Up step pages like a multi-page TIFF. | shown, pages like a multi-page TIFF, rendered by Core Graphics (spec "Formats"). | v1 |
| Output formats | 20 output formats: BMP, ECW, EMF, GIF, ICO, JLS, JPEG 2000, JPEG, JPEG XL, PCX, PBM, PDF, PGM, PNG, PPM, QOI, RAW, TGA, TIFF, WebP. No HEIC. | ImageIO formats + own PGM/PPM/QOI/PCX + WebP via libwebp; JPEG XL writing in v2; HEIC and AVIF beyond the reference. | v1 |
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
| PDN | Opens at the full canvas size (800 × 600, 694 × 424), not the small thumbnail in the file. Page 1 is the flattened image, matching Paint.NET's own thumbnail including layers with other blend modes; pages 2 … n are the layers one by one, bottom layer first ("1 / 15" for 14 layers). The status bar says 24 bits per pixel. | Spec: flattened image. Open: layers as extra pages (⌥→), like the reference. | open |
| XCF | Opens flattened at the canvas size, hidden layers left out. A Multiply layer looks applied; a layer group set to Screen is drawn as if Normal. No pages. | Spec: visible layers, normal blending with opacity, other modes a known limit. | v1 |
| PSP | A one-layer file whose only stored composite is a 300 × 225 thumbnail opens at the full 800 × 600 from its layer. No pages. | Spec: full-size composite when stored, else the layers. | v1 |

## Not checked yet

the meaning of X, options of
the remaining output formats, the advanced-options dialogs in detail, speed on a 10,000-file
folder.
