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
  TIFF, GIF (animations play, see "Animation"), BMP, camera RAW, …), plus PDF (see "Formats").
- Window title: `filename — 3 / 120`; for a multi-page file `filename — page 2 / 3 — 3 / 120`.
  A multi-page file always opens on page 1.
- The whole app is light or dark: Appearance in Settings is System (the default), Light or Dark.
  The background is Graphite (#1c1c20, the app icon's tile) in dark and Grey (#e7e7ec) in light; no
  other colours. Fit mode shrinks large images to the window and never enlarges small ones.
- The canvas fills the whole window, under the toolbar and the status strip. Fit mode keeps the
  image clear of both (it fits the area between them); a zoomed or panned image slides under them,
  so the glass takes its colour from the picture. The system's scroll edge effect dims the picture
  under the toolbar, so its title and buttons stay readable over any picture.
- The window keeps its size and position when the image changes; it never resizes itself to the
  image. Zoom changes the image inside the window, not the window.
- Zoom to Width (2) and Zoom to Height (3) fill that side of the fit area (the area Zoom to Fit uses,
  clear of toolbar and strip, beside an open info panel), enlarging small images too, within
  5 %–1600 %; the other side scrolls under the bars like any zoomed picture. From 2× on pixels show
  sharp, as for any zoom. Window resize, the info panel and full screen refit at once.
- Start edge: a new image in Zoom to Width starts at its top (centred sideways when narrower); in Zoom
  to Height at its leading edge (centred vertically): the left edge, or the right edge in Arabic and
  Hebrew. The picture itself never mirrors. Choosing either command on the image shown also goes to
  that edge, animated as a zoom step (a cut with Reduce Motion). A new page counts as a new image.
- Fit mode: Zoom to Fit (0), Zoom to Width (2) and Zoom to Height (3) set it (default Zoom to Fit,
  remembered). Actual Size (1), + / − and pinch zoom only the image shown. With Keep Zoom off, every new
  image (next, previous, first, last, after Trash or a move, a page, opening a file or folder, a new
  window) starts in the fit mode at its start edge.
- Keep Zoom (View › Keep Zoom, ⇧L, ticked while on; default off, remembered): a new image keeps the
  zoom of the one before, factor or fit mode, and its scroll position: the point at the centre of the
  clear area keeps its fraction of the picture's width and height, so a same-sized series shows the
  same pixels and bottom-right stays bottom-right. It follows the current zoom, never one taken when
  it was switched on.
- A fill mode's zoom decodes at the next halving step like any zoom: into the 8-image cache when that is
  no larger than the image's fit decode, else into the one-image full-size cache, so browsing images
  that need more than their fit decode isn't prefetched (the not-prefetched budget applies).
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
| H / V | flip horizontal / vertical (lossless, see "Rotate and flip") |
| I | toggle info panel |
| F, Return | toggle full screen; Esc leaves full screen (and never quits the app) |
| 0 | zoom to fit |
| 1 | actual size (1 image pixel = 1 screen pixel) |
| 2 / 3 | zoom to width / zoom to height |
| ⇧L | Keep Zoom on / off (⇧L and ⇧A are the only Shift letters; Caps Lock L still rotates left) |
| + / − | zoom in / out (×1.1 steps, 5 %–1600 %) |
| ⌥→ / ⌥← | next / previous page of a multi-page file (TIFF, …); nothing past either end |
| F7 / F8 | move / copy the current file to a folder (see below) |
| F5 | refresh the folder (also ⌘R; see "Refresh") |
| F2 | rename the current file (see "Rename") |
| T | thumbnail grid on / off (also ⇧⌘T; see "Thumbnail grid") |
| Space in the grid | Quick Look of the selection |
| W | start / end the slideshow in full screen (also ⇧⌘F; see "Slideshow") |
| ⇧A | play the slideshow in the window / stop it |
| Space during a slideshow | pause / resume |
| X / D, compare only | swap the images / show the difference (see "Compare") |
| Esc, compare only | stop comparing (in full screen the next Esc leaves full screen) |
| ⌦ (forward delete) | Move to Trash, like ⌘⌫ |
| O / B / M | Open… / Batch Convert… / minimise the window (as ⌘O / ⌘B / ⌘M) |
| P / A / S | Settings / About / Save As…, each added with its feature (milestones 2–3) |

Single keys for commands match the reference viewer, for people switching over; the ⌘ shortcuts stay for Mac users.

### Mouse and trackpad

- Double-click the image: toggle full screen.
- Dragging pans a zoomed image (the image follows the pointer); it does nothing when the image
  fits. No selection rectangle.
- Right-click (or Control-click) opens a context menu with the window's actions: Copy, Rotate
  Left / Right, Flip Horizontal / Vertical, Adjust Date Taken…, Rename…, Move to Folder…, Copy to Folder…, Move to Trash, Show in Finder, Open With,
  Share, Set as Desktop Picture; during a slideshow Pause / Resume Slideshow and End Slideshow come first.
- A click on the file name in the window title renames the file (see "Rename"); dragging the title
  still moves the window.
- Two-finger scroll (or a mouse wheel) pans a zoomed image.
- Pinch zooms in and out about the pointer, following the fingers (no animation), within the
  same 5 %–1600 % as + / −.
- Swiping sideways changes images the way the Mac swipes between pages: with two fingers (or three,
  per the trackpad setting), only while the image has nothing to pan sideways; a swipe goes the way of
  the arrow key it moves towards (mirrored in right-to-left languages). A mouse wheel never changes images.

### Toolbar

For mouse users, the viewer window has a standard macOS toolbar: previous,
next, thumbnails, rotate left, rotate right, zoom out, zoom to fit, zoom in, info panel, Share (`square.and.arrow.up`, tooltip
"Share"), Move to Trash, plus previous / next page
for a multi-page file only. Each button does what its key does and has a tooltip naming that key. View › Hide Toolbar hides it
(remembered), and View › Customize Toolbar… changes it, as in any Mac app. Customize Toolbar… also
offers five items that aren't in the default set: Flip Horizontal (tooltip "Flip horizontal (H)"), Flip
Vertical ("Flip vertical (V)"), Zoom to Width ("Zoom to width (2)"), Zoom to Height ("Zoom to height (3)")
and Keep Zoom (a toggle, `pin`, "Keep zoom (⇧L)"). Hidden in full screen; it slides in with the menu bar when the pointer is at the top (macOS 15 and later).

"Hide toolbar and status bar while viewing" (Settings › Viewer, off): in a window, once the
pointer has rested over the picture for 2 s, the toolbar and status strip fade out (200 ms). Moving
the pointer, reaching the window's top edge, or any key except the browsing keys (← → Space
Backspace Page Up/Down Home End) brings them back at once; browsing keys keep them hidden. Every
toolbar command is also in the menus, so hiding never takes a command away.
Mac SF Symbols, never icons taken from another viewer.

### Menu commands

⌘N New from Clipboard, ⌘O Open…, ⌥⌘O Compare With…, ⇧⌘F Start / End Slideshow, ⌘⌫ Move to Trash, ⌘B Batch Convert…, ⇧⌘S Save As… (the current image in any writable format, with that format's options, orientation
applied, never overwriting without the standard Mac replace prompt; afterwards the window shows the saved file in its folder; if Featherview can't read the format it saved, the window stays on the original), ⌘C Copy (the current image, full resolution,
orientation applied), ⌘Q Quit. Menus also list the single-key commands
(the single key in the shortcut column, also for commands that have a ⌘ shortcut, which keeps
working) so they are discoverable. Single keys are menu shortcuts only while a
menu is open, so typing in the batch window's text fields never triggers viewer actions.

Like Finder and Preview, File holds what acts on the file (Open, Open Recent, Save As…, Rename…, Share, Move /
Copy to Folder…, Move to Trash, Show in Finder, Open With, Always Open with Featherview, Batch Convert…) and Image
what moves through or changes the picture (Next / Previous, pages and frames, rotate and flip, Adjust Date
Taken…, Set as Desktop Picture, Show Info, All Metadata…). View lists "Zoom to Fit  (0)", "Actual Size  (1)", "Zoom to
Width  (2)", "Zoom to Height  (3)", Zoom In, Zoom Out, then "Keep Zoom  (⇧L)"; Image has "Flip Horizontal  (H)"
and "Flip Vertical  (V)" after the rotate items. File starts with New from Clipboard, Open…, Open Recent, Compare With… (and Stop Comparing while
comparing); Rename…
and Share follow Save As…. View has Sort By, then "Refresh  (F5)" (⌘R), then Follow New Files, then the slideshow items; Image ›
"Random Image" follows Previous. The Window menu has Float on Top, then only the viewer windows: Batch and
About open from their own commands.

The app menu has Check for Updates… below About (see "Updates"). The Help menu repeats About's links:
Featherview Website and Source Code (browser); Supported Formats, MIT License and Acknowledgements
(About opens with that text); and, last, Report a Bug…:
it opens the browser at a new GitHub issue from the repo's bug report form
(`.github/ISSUE_TEMPLATE/bug_report.yml`), with Featherview version and build, macOS version and Mac
model filled in; the person describes what happened.

After Featherview crashed, the next launch offers, once per crash and at the earliest 10 seconds after
launch (like the update check): "Featherview quit unexpectedly last time." with "Report…" and "Not Now".
Report… opens the same bug report form as Help › Report a Bug…, with the crash summary (exception type
and the crashed thread's first 15 frames) in a "Crash report" field. Nothing is sent by the app. Only
Featherview's own reports count (its process, not the extensions'); only reports newer than the last one
offered.

### Rotate and flip

Lossless: only the EXIF orientation tag changes. Supported for JPEG, HEIC and TIFF (by content, not
extension; HEIC sequences are not); other formats show "Lossless rotation works with JPEG, HEIC and
TIFF only". The file is rewritten through a temp file and swapped in, so a failure (e.g. read-only
folder) leaves the original untouched and shows "Couldn't rotate <name>".
In a multi-page TIFF only page 1 can be rotated: ImageIO can't change a later page's tag without
re-encoding every page, so pages 2 and on show "Only page 1 of <name> can be rotated losslessly"
and the file stays untouched.

Flip Horizontal (H) and Flip Vertical (V) mirror the picture as shown (left–right / top–bottom),
whatever its orientation, and write it the same way, through the same queue as rotate (one change at a
time, none lost). Same formats and limits, with "Lossless flipping works with JPEG, HEIC and TIFF only",
"Only page 1 of <name> can be flipped losslessly" and "Couldn't flip <name>". A flip shows at once, with
no animation; a rotation keeps its animated turn. R on a mirrored picture still turns it clockwise on
screen.

### Adjust Date Taken

Image › "Adjust Date Taken…" (no key; also in the context menu; enabled as Rotate is, and in the grid
while cells are selected) opens a sheet "Adjust Date Taken": "Original" (the date taken, or "None, file
date …"; "and 3 more" for a grid selection) and "Adjusted" (a date-and-time picker with seconds,
starting at the original), the note "The file's date changes too.", Cancel and Adjust (disabled while
the date is unchanged). Adjust changes the file in place, losslessly, as the batch's Date Taken step
does: a rewrite to a temp file next to it, swapped in (a symlink's target is changed), then its modified
and created dates follow; a failure leaves the original untouched. Only JPEG, HEIC, TIFF and PSD (by
content); for one file of another type: "The date taken can be changed in JPEG, HEIC, TIFF and PSD
files only", any other failure "Can't change the date taken of <name>". On a grid selection the first
selected file gets the adjusted date and the others shift by the same amount, as Photos does; one
failure never stops the rest ("3 files couldn't be changed"). The info panel, status strip and grid
refresh afterwards.

### Refresh

F5 and ⌘R rescan the folder now, also with Follow New Files off: new images join the list in sort
order, vanished ones leave it, and the current image stays on screen. If the current file is gone,
the image at its position shows, as after Move to Trash. Disabled without a folder.

### Random image

Image › "Random Image" shows a random other image of the list, never the one already shown. Nothing
happens with fewer than two images. Off during a slideshow (it has its own order) and in the grid.
It has no single key: the menu item only.

### Desktop picture

Image › "Set as Desktop Picture" (also in the context menu) is a submenu: Fill Screen (the default), Fit
to Screen, Stretch to Fill Screen, Center. Every screen gets the picture, with no confirmation (System
Settings undoes it); the file is used where it is. Fit and Center leave the rest of the screen black.
Only for files macOS itself shows (not Featherview's own formats, not PDF); otherwise disabled. Failure:
"Couldn't set <name> as the desktop picture".

### Open Recent

File › Open Recent lists the system's recent documents, newest first, as many as System Settings ›
Desktop & Dock › "Recent documents" allows (10 by default), then "Clear Menu"; empty, it shows "No Recent
Files". Items show the file or folder name; two items with the same name get " — <folder>" after it.
Files that are gone or in the Trash are left out (checked when the app becomes active and after its own
moves and Trash). Counted as opened: an image or folder opened with ⌘O / O, dropped on the window,
opened from Finder or the Dock, chosen in Open Recent, the file New from Clipboard opens, and a file
written by Save As. Not counted: browsing, the folder chooser, Follow New Files, compare. A renamed or
moved file keeps its entry (the system follows the file). The Dock menu shows the same list, kept by
macOS itself; it may show a renamed file's old name until macOS refreshes it. The list is read after the
first image is drawn, never on the launch path.

### Rename

File › "Rename…  (F2)", F2, the context menu's Rename… or a click on the file name in the window title
turns the title's name into a text field, as Preview does: the whole name, the part before the extension
selected, as Finder does. Return renames; clicking elsewhere renames too; Esc cancels. In full screen or
with the toolbar hidden the same field shows in a small sheet ("Rename", Cancel / Rename).

- Spaces and line breaks at either end are trimmed; an unchanged or empty name does nothing.
- Refused, with a message in the window's message box (under the field in the sheet): "A name can't contain “/” or “:”." (also for control
  characters), "A name can't start with “.”: the file would be hidden.", "That name is too long." (more
  than 255 UTF-16 units), "“B.jpg” is already taken. Choose a different name.". Return keeps the field
  open on a refusal. Nothing is ever overwritten; a name differing only in case renames. Any other
  failure: "Couldn't rename <name>".
- A changed extension asks first, as Finder does: "Are you sure you want to change the extension from
  “.jpg” to “.png”?" (or "… remove the extension “.jpg”?"), "The image may then open in another app, or
  not at all.", buttons "Keep .jpg" (default) and "Use .png" (or "Remove").
- Sidecars (`.xmp`, `.aae`, `.thm`) follow under the new name with their own extension while "move,
  copy and trash sidecar files" is on. If a sidecar's new name is taken, nothing is renamed and the
  message names that sidecar.
- Afterwards the title shows the new name, the list re-sorts in the current sort order and the
  position updates; the picture stays on screen without a new decode. Disabled in the thumbnail grid,
  for an image whose file is gone and for an unsaved clipboard image. Waits for a rotation, move or
  Trash in progress, like they wait for each other.

### Sort By

View › Sort By: Name (Finder order), Date Modified, Date Taken, Size, Kind, then Ascending /
Descending, ticked on the current choice. Global and remembered (default Name, Ascending): every
viewer window re-sorts at once and every folder opens in it. Changing it keeps the current image on
screen and updates its position.

- Ties, and files whose value can't be read, fall back to name order, ascending; missing values go
  last in both directions. Name Descending is Finder order reversed.
- Date Taken is EXIF `DateTimeOriginal`, else the modification date. Kind is the system's name for the
  extension's type ("JPEG image"), else the extension in capitals.
- Name, Date Modified, Size and Kind read no file contents, so a folder opens on its first image in that
  order within the open budget. Date Taken reads every file's header: the folder opens in name order,
  its first image by name shows at once, the dates are read in the background, then the list re-sorts
  with the shown image kept. Nothing blocks.

### Share

A toolbar button, File › Share and Share in the context menu open the system's share picker for the
current file (Mail, Messages, AirDrop, …). Disabled in the grid, for an image whose file is gone and for
an unsaved clipboard image.

### Float on Top

Window › "Float on Top" (ticked while on) keeps that window above other apps' windows. Per window, not
remembered across launches, as in QuickTime Player. Disabled in full screen.

### New from Clipboard

File › "New from Clipboard" (⌘N), first in the File menu, shows the clipboard's image in the window in
use (the last active one when none is), covering its list: the list stays behind it, unchanged.

- A copied image file Featherview reads (Finder's Copy) opens that file, as ⌘O would. Otherwise the
  first image type on the clipboard that ImageIO decodes (PNG, TIFF, JPEG, HEIC, …), full size,
  orientation applied. Disabled when neither is there (checked when the app becomes active, when a menu
  opens and on ⌘N). An image that can't be decoded shows "Can't open the image on the clipboard".
- It ends a slideshow, the grid and compare and closes the folder chooser, the F7 / F8 panel and the
  info panel. It shows as an unsaved image: title "Untitled" with the window's edited dot, status strip
  with pixel size and zoom only. Zoom, full screen, ⌘C and Save As work; everything that acts on a file
  is disabled.
- Save As (S, ⇧⌘S) writes it in any writable format, named "Untitled", in the list's folder (else
  Pictures), then shows the saved file in its folder.
- Leaving it asks first, in a sheet: "Do you want to save the image from the clipboard?" / "If you
  don't save it, it's gone." with Save… (default), Don't Save (⌘D) and Cancel. Asked for every key that
  moves to another image, ⌘O / O, a drop, a Finder file sent to this window, Open Recent, ⌘N again,
  closing the window and ⌘Q (once per unsaved image). Save… saves into the list and then carries on with
  what was asked. After leaving, the image shown before shows again (Home / End go to the first / last).

### Follow New Files

View › "Follow New Files" (ticked while on): per window, off by default, not remembered, disabled
without a folder. While on, the window watches its folder. After the folder has been quiet for 200 ms
it rescans the names, adds new images to the list in sort order and drops vanished ones, then shows the
newest arrival (latest modification date) once its size is above zero and has stayed the same for
250 ms, so a file still being copied or exported isn't shown half-written (given up after 30 s). A burst
of files shows its newest once. Arrivals don't interrupt a rename field, the folder chooser or the F7 /
F8 panel: the list takes them, the window stays. While an unsaved clipboard image shows, the rescan waits
until it is left. A current file deleted elsewhere stays on screen until the next key. Opening another
folder moves the watch there; the folder renamed or deleted, or the window closed, turns following off.
Nothing is watched while it is off, so launch and browsing pay nothing.

### Slideshow

- View › "Start Slideshow  (W)" (⇧⌘F, Preview's shortcut) plays the viewer's list in full screen from
  the current image; View › "Play in Window  (⇧A)" plays it in the window. While one runs they read "End
  Slideshow  (W)" and "Stop Playing  (⇧A)", and "Pause Slideshow  (Space)" / "Resume Slideshow  (Space)"
  appears; the context menu gets Pause / Resume Slideshow and End Slideshow at its top. Disabled without
  a current image and while the folder is still being listed. W or ⇧A in the grid start from the focused
  cell. Starting leaves compare.
- View › "Slideshow Options" (a submenu, so it can be changed mid-show from the menu bar that slides in
  over full screen): "Show Each Image For" 1, 2, 3, 5, 10, 20, 30 or 60 seconds (default 5), then
  "Shuffle" and "Repeat" (both off). All remembered; no Settings entry.
- Order: from the current image to the end of the list, then the end. Shuffle: the current image first,
  then every other image once in random order. With Repeat each further round is the whole list,
  shuffled anew, never starting with the image the last round ended on. Shuffle never changes the
  viewer's list: afterwards ← / → go to the shown image's Finder neighbours, and the title and overlay
  show its Finder position.
- Changing options while playing: a new interval applies to the image on screen at once (counted from
  when it showed); toggling Shuffle restarts the round from the image on screen in the new order; Repeat
  only changes what happens at the end.
- Timing: an image's interval starts when it is on screen. A next image not decoded by its due time
  shows as soon as it is, and its interval counts from then; ticks never queue up. Started from a
  window, the first interval starts once the window is in full screen. A step, a rotation, a zoom or a
  page change gives the image a full interval again; so does resuming after a pause.
- While a slideshow runs, prefetch follows the play order (at fit the next two and the previous one,
  zoomed the next and the previous one, into the next round with Repeat), so each change is a
  prefetched swap.
- While it plays (not paused or finished) in a visible window, the display doesn't sleep; the Mac may
  still sleep. Minimized, fully covered or on another Space, the slideshow waits and goes on with a full
  interval when visible again.
- Full screen only: a small glass capsule at the bottom centre (Previous, Play / Pause, Next, End;
  tooltips "Previous (←)", "Pause (Space)" / "Play (Space)", "Next (→)", "End slideshow (Esc)") shows
  when the pointer moves and fades out after 2 s at rest unless the pointer is over it; paused or
  finished it stays up. The pointer hides with it when Settings › Full Screen › "Hide the pointer" is on,
  never on each image change. Playing in the window shows no capsule.
- The end (Repeat off): after the last image's interval the slideshow is finished: it stays on that
  image (in full screen if it was), Space or Play plays a new round from the start, → does nothing and ←
  goes back, paused. Esc, W or ⇧⌘F go back to the window on the image shown; ⇧A stops in place.
- Esc, W and ⇧⌘F end the slideshow and leave full screen if the window is in it; ⇧A ends it and leaves
  the window as it is. F, Return, double-click and the green button toggle full screen and the slideshow
  goes on in the other form.
- Keys while it runs (everything else as in the viewer): → ↓ Page Down and a swipe step to the next
  image in play order, ← ↑ ⌫ Page Up to the previous (panning a zoomed image first); paused stays
  paused; nothing past either end (with Repeat, → past the end starts the next round). The folder
  chooser never opens. Space pauses and resumes. Home, End and Random Image do nothing. R / L, H / V, ⌦
  / ⌘⌫, F7 / F8, S, ⌘C, I, G, ⌥→ / ⌥←, 0–3, + / − work, so a slideshow can be used to cull: Trash or a
  move takes the image out of the play order and the next one in play order shows at once ("show the
  next image" off doesn't hold it here; at the end of the order the previous one shows); the last image
  gone ends the slideshow. While a panel, sheet or alert is open a due image waits a full interval more.
- Opening a file or folder, compare, T (the grid) and closing the window end the slideshow.
- Unreadable files are skipped at once in the direction of travel, without a message (turning back at
  an end of the order). When every image failed in a row it finishes on the last one with its "Can't
  open <name>".
- Animated images play while on screen; the interval alone decides when the next image comes. G pauses
  the animation, not the slideshow.
- Image changes are cuts; the capsule fades by opacity only, which Reduce Motion keeps. Entering full
  screen is the system's animation.

### Compare

Two images side by side in the viewer window, as a mode of it (two windows can't stay in step).

- File › "Compare With…" (⌥⌘O) opens an open panel for images, starting in the current image's folder,
  with "Choose an image to compare with <name>"; the chosen file becomes the second pane. Chosen again
  while comparing, it replaces the second image. Disabled without a current image, for an image whose
  file is gone and in the grid. In the grid, Image › "Compare" compares the two selected thumbnails (in
  list order), enabled with exactly two selected. Comparing a file with itself is allowed.
- Layout: two panes of equal width, the first at the leading side (on the right in right-to-left
  languages), a 1 pt divider between them. Each pane is its own canvas between the toolbar and its own
  floating status strip: name · pixel size · zoom · file size · date; the position stays in the title.
  The window never resizes. The info panel closes on entering; I does nothing. Title: "<first> and
  <second>", then the first image's counter. The second pane's context menu: Swap Images, Stop
  Comparing, Show in Finder.
- In step (View › "Zoom and Pan in Step", on by default, remembered): content-aligned, not pixel for
  pixel. The second picture is drawn at the first's zoom × min(w₁/w₂, h₁/h₂) of the displayed
  (orientation-applied) sizes, so it covers the box the first is drawn in, centred, and the same detail
  sits at the same place in both panes. Two images of the same size line up pixel for pixel; an image
  and its resized copy line up too. At fit, the first fits and the second matches it (a smaller second
  image is drawn enlarged; its strip shows its own zoom). Whichever pane is scrolled, dragged or pinched
  leads, the other follows. Zoom keys, the toolbar's zoom buttons, 0–3 and pinch zoom the first pane,
  the second follows. Zoom steps are cuts in compare (two animations would drift apart). At the edge of
  the 5 %–1600 % range the panes stop lining up.
- In step off: each pane keeps its own zoom and pan; zoom keys, 0–3 and pinch act on the pane last
  clicked, scrolled or pinched (the first at first). Turning it on again snaps the second to the first.
- Stepping: → ← Space ⌫ Page Up / Down Home End, the toolbar's arrows and swipes step the first pane
  through the viewer's list as usual (end-of-folder rules and folder chooser unchanged); the second
  stays. Zoom and the relative scroll position stay. Arrow keys pan the leading pane first when it has
  something to pan.
- Swap: X, View › "Swap Images  (X)" and a button on the second pane's strip (`arrow.left.arrow.right`,
  tooltip "Swap Images (X)") exchange the files: the first pane shows the second file (selected in the
  list when it is there, else the window opens its folder and stays in compare). Zoom stays. Disabled
  while the second pane can't open.
- Difference: D and View › "Show Difference  (D)" (ticked while on) show |first − second| per channel
  (R, G, B) in the second pane, both flattened over black, not amplified. The second is scaled and
  centred as for in step; outside it the first shows through. Computed off the main thread from the two
  decodes on screen at the first's decoded size, recomputed when either changes; only the latest result
  shows. The second pane then draws it exactly as the first draws its picture; its strip reads
  "Difference". Available once both images are decoded; stays on across steps and swaps. While it is on
  an animation in the first pane holds its first frame.
- Leaving: Esc (a running slideshow ends first; in full screen the next Esc leaves full screen), File ›
  "Stop Comparing", the close button on the second pane's strip (`xmark`, tooltip "Stop Comparing
  (Esc)"), opening a file or folder into the window, T, starting a slideshow, and the list running
  empty. The first image stays at its zoom; the second's decodes go.
- Every command on "the current image" (R / L, H / V, ⌘C, S, F7 / F8, Trash, pages, Show in Finder,
  Open With, Always Open…) acts on the first pane. The second shows page 1 and, for animations, the first
  frame.
- Memory: the second image's fit decode goes in the viewer's 8-image cache (a swap or a step onto that
  file reuses it); beyond fit its zoom decode goes in a one-image cache that exists only while
  comparing; plus one difference image. The second file joins the decode window right after the current
  image, so a held arrow key never drops it.
- The second image unreadable or gone: "Can't open <name>" in its pane; compare stays.

### Thumbnail grid

The grid is a mode of the viewer window, not a window of its own.

- T, View › "Show Thumbnails  (T)" (⇧⌘T) and a toolbar button (`square.grid.2x2`, tooltip "Thumbnails
  (T)", in the default set before Rotate Left, toggled while on) switch to it; in the grid the item reads
  "Show Image  (T)". Disabled while the window has no list (empty window, folder without images, still
  opening). Entering it ends a slideshow, leaves compare and closes the info panel.
- It opens on the current image, selected and scrolled to the middle. T, Return or double-click go back
  to the viewer on the focused cell (the last one clicked or moved to); Esc goes back to the image shown
  before T (in full screen a second Esc leaves full screen). Opening any file or folder leaves the grid.
- Cells are the viewer's list, in its order, so unreadable and non-image files the list holds get
  cells too. The grid follows the list (the scan finishing after T, a removal, a new sort) and keeps the
  selection.
- Cell: a square, the thumbnail fitted
  inside, aspect kept, never enlarged, orientation applied, with the picture hairline and no shadow; the
  file name below in one line, truncated in the middle. Selected: a toggled-pill backdrop behind the
  square and the name in an accent capsule. Loading: a card-filled square. Can't open:
  `photo.badge.exclamationmark` in tertiary. No folder tree and no subfolders (Finder and the folder
  chooser choose folders).
- Hovering a cell shows its name, then pixel size, file size, position ("3 / 120") and date, read once
  the pointer rests (never while scrolling). A file that can't be opened shows "Can't open <name>".
- Size: whole columns always fill the width, as in Photos. The remembered size (64–256 pt, default 128)
  is a target: the grid takes the column count whose cells come nearest to it, then widens the cells
  (whole points) until the row fills the width between the side margins, gaps kept; the count moves
  on if that leaves the cells outside 64–256 pt (one column, as wide as the window, when even 64 pt
  doesn't fit twice). Resizing the window keeps the target, so cells grow until a column more fits.
  The slider at the trailing end of the status strip sets the target, so dragging it steps one column
  at a time; + / − (and View's "Larger Thumbnails  (+)" / "Smaller Thumbnails  (−)", which replace
  Zoom In / Out) and a pinch on the trackpad take one column away or add one (a pinch: one column per
  0.15 of magnification, as long as the fingers move), and the new cell size becomes the target.
  Nothing happens when no column count is left in the range. With the strip hidden the keys still
  work. The toolbar's zoom buttons are disabled in the grid.
- Thumbnails decode at the cell's pixels rounded up to 128, 256, 384 or 512, so dragging the slider
  re-decodes only when it crosses a step, and a larger cached thumbnail serves a smaller cell. 8 bits in
  the screen's colour space, never HDR. A file's embedded thumbnail is used when it is large enough (or
  as large as the image) and its aspect matches the image's within 2 % (camera thumbnails with black
  bars never show); otherwise the image is decoded in the same job, with no blurry first pass. Animated
  files show their first frame, multi-page files page 1; nothing plays in the grid.
- Only visible cells decode, then one screen ahead in the scroll direction, nearest first in reading
  order; each scroll drops waiting jobs for cells that left. The grid has its own decode queue
  (2–6 at once, by core count), apart from the viewer's.
- Memory: the thumbnail cache holds at most three screens of pixels (3 × the largest screen's pixel
  area × 4 bytes, ≈ 71 MB on a 3024 × 1964 screen), whatever the number of files. It is made at the
  first T, kept while the window stays on its list (T back and forth is instant) and emptied when the
  window opens a file or folder or closes.
- Selection: click, ⇧-click a range from the last click, ⌘-click to add or remove one, arrows and
  ⇧-arrows (mirrored in right-to-left languages), ⌘A (Edit › Select All); Home / End go to the first /
  last cell. No selection rectangle. The grid takes the keyboard as soon as it opens.
- On the selection: Space opens Quick Look (Featherview's own formats preview through its extension);
  with one cell selected the arrows move the selection one cell and the panel follows, with several the
  panel steps through them; Space again closes it. ⌦ and ⌘⌫ move the selection to the Trash without
  asking (⌫ alone does nothing); F7 / F8 move or copy it through the destination panel ("Ask before…"
  asks once for all: "Move 3 images to <folder>?"); B or ⌘B opens the Batch window with the selection
  added; Image › Adjust Date Taken… changes the selection (see "Adjust Date Taken"). After a removal the
  cell after the last removed one is selected (the one before it at the end); the grid closes when the
  list runs empty. One failure never stops the rest; the message names the file when one failed
  ("Couldn't move <name> to the Trash"), else the count ("Couldn't move 3 images to the Trash").
  F5 refreshes as in the viewer. ⌘C (Edit › Copy) puts the selected files on the clipboard, as Finder's
  Copy does, so they paste as files into Finder, Mail or any app. File › Show in Finder selects them
  in Finder.
- Right-click (or Control-click) on a cell: a cell already selected keeps the selection; any other
  cell becomes the selection and the focus first, as in Finder. A click between cells shows no menu.
  The menu acts on the selection: "Show Image" (the clicked cell, as Return), then "Copy", "Show in
  Finder", then "Move to Folder…", "Copy to Folder…", "Batch Convert…", then "Move to Trash". No key
  names in the titles; each does what its key does.
- Dragging a selected cell out of the window drags the selected files (one item each, in list order,
  the cells' pictures as the drag image), so Finder, Mail or any app takes them. Copy only: Finder
  copies them even on the same disk (the folder never changes under the viewer), dropping on the
  Trash does nothing, and a drop back on a Featherview window does nothing. A plain click on a cell
  inside a selection of several keeps the selection until the mouse goes up without dragging, then
  selects only that cell; a drag that starts on a cell outside the selection first selects that cell.
  ⇧- and ⌘-clicks change the selection at once; a drag from a cell they left selected drags the
  selection.
- Strip and title: the strip shows the focused file's pixel size, file size, position and date (no
  zoom), or "12 of 120 selected" while several are selected, then the slider. The title is the folder's
  name with "— 120 images".
- Keys that act on one viewed image do nothing in the grid, and their menu items are disabled: R, L, H,
  V, I, 0–3, ⇧L, S, F2, ⌥→ / ⌥←, G, ⇧⌘S, Next / Previous, Random Image, Open With
  (also ⌥1–⌥3), Always Open with, Rename… and Share. O, P, A, M and F keep their meaning.

### Move to Trash

⌘⌫ moves the current file to the Trash (recoverable) and shows the following image.

### Info panel

I (Image › Show Info) toggles a 280 pt side panel. Design: <https://claude.ai/artifact/Lf6bXo8PaC2Exi6A6Unvmx>
(B2-1b-2); look in `docs/DESIGN.md` "Info panel". Everything is read off the main thread from the file
and the already decoded picture; missing values, and groups with nothing in them, are left out (no
empty rows or cards). Text is selectable. Nothing in the panel uses the network.

- **Header:** file name (cut in the middle, full name as tooltip); one line "JPEG · 3,000 × 2,000 ·
  476 KB" (format, dimensions with orientation applied, file size; a RAW file shows its own size);
  when the photo has a place, a pin and the short place name ("Andermatt, Switzerland").
- **Histogram:** 60 pt tall, full panel width, quarter grid. Luminance (default) or RGB, switched
  with a small Luminance / RGB control; the choice holds for every image until the app quits.
  Luminance is a line with a faint fill in the accent; RGB adds thin red, green and blue lines under
  it. A clip mark sits in each bottom corner: outlined, filled in the accent when more than 0.1 % of
  the pixels are at the darkest or brightest level; clicking it shows "Shadows: 2.4 % clipped" /
  "Highlights: 0.0 % clipped". 256 levels per channel, computed from the screen-size picture
  already decoded (no extra decode; zoomed into a picture never shown at fit, from the zoomed one). An HDR picture shows the standard range up to a dashed
  1.0 marker, then the brighter part up to its headroom ("3.2×").
- **Groups,** each a card with a glyph, a title, a chevron and, when closed, a one-line summary.
  Clicking the header (or Space / Return on it) opens and closes it. Which groups are open holds for
  every image and every window until the app quits; at launch Camera and Location are open.
  - **Camera** (closed: the camera model): four tiles with the bare number big and a glyph and unit
    under it: shutter "1/250 · sec", aperture "8 · ƒ stop", ISO "100 · ISO speed", focal length
    "35 · mm" (tooltip "53 mm equivalent"). Chips: exposure bias ("−0.7 EV"), flash ("Flash" /
    "No flash"), white balance ("Auto" / "Daylight" / "Manual"…), metering ("Multi-segment",
    "Centre-weighted", "Spot"…). Rows: Lens, 35 mm equivalent (only when it differs from the focal
    length), Taken.
  - **Image** (closed: "P3 · 8-bit · HDR"): Dimensions with megapixels ("3,000 × 2,000 · 6.0 MP"),
    Colour profile, Bit depth ("8 bits per channel"), HDR ("Gain map, up to 3.2×"), Software.
  - **Location** (closed: the altitude, or nothing at sea): the full place name as the first line
    (13 pt semibold, up to two lines), then Latitude ("46.6356° N"), Longitude, Altitude, and
    "Open in Maps" (opens the coordinate in the Maps app; nothing loads before the click).
  - **Description** (closed: the rating as stars): Title, Caption, Keywords, Rating, Creator,
    Copyright, Comment — merged from EXIF, IPTC, XMP and the JPEG/PNG comment, read only.
  - **File** (closed: the modification date): Folder, Modified, Created, "Show in Finder".
- **"Show all metadata…"** at the bottom opens the All Metadata window (below).

**Keyboard and accessibility:** the panel works without a mouse and shows where the focus is.
- With the panel open, Tab moves the focus from the picture into the panel (the Luminance / RGB
  control first), then through the clip marks, each group header, the buttons of open groups, and
  "Show all metadata…"; ⇧Tab goes back; Tab after the last control returns to the picture. Esc puts
  the focus back on the picture. Clicking the picture does too.
- The control the keyboard focused shows the focus ring (the accent at half opacity, as the system draws
  it, 2 pt, 1 pt outside its shape), with or without System Settings › Keyboard › Keyboard navigation;
  a click focuses without the ring, as elsewhere on the Mac; it is never hidden by the panel's scrolling (the
  panel scrolls the focused control into view).
- Space or Return acts on the focused control (opens or closes a group, presses a button, switches
  the histogram mode); ← / → on the mode control switch it. All other viewer keys (← / → to browse,
  R, L, I, F, …) keep working while the focus is in the panel; when I closes the panel the focus
  returns to the picture.
- VoiceOver: the panel is a group named "Info"; each group header is a heading with its state
  ("Camera, collapsed, Fujifilm X-T5"); tiles and chips read as one phrase ("Shutter speed 1/250
  second", "Exposure bias minus 0.7"); the histogram reads its mode and clipping ("Luminance
  histogram, highlights clipped 2.4 %"); clip marks and buttons are buttons with labels.
- Increase Contrast thickens hairlines and raises secondary text to primary; Reduce Motion makes
  opening and closing groups a cut; Dynamic Type isn't offered by macOS, so sizes stay as designed.

**Place names** come from data shipped in the app (GeoNames places with at least 1,000 people;
Natural Earth seas, oceans, deserts and mountain ranges), looked up on the Mac:
1. A place within 25 km: header "Andermatt, Switzerland", Location "near Andermatt, Uri,
   Switzerland" (the nearest by distance, never weighted by population). A city district carries its
   city, the nearest larger place in the same administrative areas: "Berlin-Neukölln" in Germany,
   Austria and Switzerland, "Camden, London" elsewhere.
2. Else, a sea or ocean containing the point, with a place within 200 km: "North Atlantic, off
   Gambia" / "North Atlantic Ocean, off Banjul, Gambia". The header drops "Ocean" only when more
   than one word is left ("Indian Ocean, off Sri Lanka" keeps it).
3. Else, a desert or mountain range containing the point, with a place within 500 km: "Sahara,
   near Tunisia" (both forms).
4. Else the sea, ocean or region alone ("North Pacific Ocean"); else no place, coordinates only.
Country names follow the app's language (from macOS), and so do the names of places of 15,000 people
or more, their districts and states where GeoNames has one in that language ("Nürnberg-Wetzendorf,
Bayern, Deutschland" on a German Mac); a district never mixes scripts (in Japanese it stays
"Nuremberg-Wetzendorf" rather than half translated). Other place names and sea and region names are as
the data gives them, except that names the data writes in capitals are title-cased ("AHAGGAR MTS." reads
"Ahaggar Mts."). The data loads on the first geotagged picture, off the main thread; launch and browsing
budgets stay as they are. The Quick Look extensions don't carry it.

**All Metadata window** (also Image › All Metadata…, ⌥⌘I): a separate window, "Alpine Dusk.jpg — All
Metadata", that follows the current image of the frontmost viewer (a sheet would block the arrow
keys). Groups EXIF, GPS, IPTC, XMP, TIFF (and others ImageIO reports), each with a count; every row
shows a readable name with the raw tag name under it and the value on the trailing side. Internal
entries (offsets, thumbnail data, binary maker notes) are hidden; the footer says how many. A search
field filters names, tags and values. Fully usable from the keyboard: ⌘F focuses the search field,
Tab moves between search field and list, ↑ / ↓ move the selection (⇧ extends it), ← / → close and
open the selected row's group, Home / End jump to the first / last row, Return in the search field
moves to the first match, Esc clears the search, then closes the window; ⌘C copies the selected rows
("Exposure time (ExposureTime): 1/250 s", one per line), ⇧⌘C copies everything; ⌘W closes it.

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
It asks instead. From macOS 26.4, macOS confirms every change of a type's default app with a prompt
of its own, one per type, and there is no way to change several types in one prompt (a default for
`public.image` doesn't reach the image types, and rank Owner doesn't beat Preview). So each choice
the user makes claims one type: never more than one macOS prompt per click.

- Once, at the first launch from an Applications folder (`/Applications` or `~/Applications`, not
  from the disk image, `build/` or a translocated copy), and only while Preview or no app opens
  JPEG: a dialog "Open JPEG images with Featherview?", "Featherview can open them instead of
  Preview. Other image types can follow in Settings › Browsing.", buttons "Use Featherview"
  (default) and "Not Now". "Use Featherview" makes it the default for JPEG only. Either answer ends
  the asking; it never comes back by itself.
- Settings › Browsing, group "Default app": one row each for JPEG, PNG, HEIC, GIF, TIFF and
  WebP (the system's name for the type), the app that opens it now, and a "Use Featherview" button
  (off while Featherview opens it). Footer: "For any other type, open an image of it and choose
  File › Always Open with Featherview."
- File › "Always Open .png Files with Featherview" (the current file's extension): the same for
  the current file's type, whichever app opens it now (off while Featherview opens it). Never offered for PDF or anything conforming
  to it: Featherview shows PDFs as images, it isn't a PDF reader.
- Choosing Keep in macOS's prompt, or macOS refusing the change, changes nothing and shows no
  message (the two look alike to the app; the Settings row shows which app opens the type).
  Undo is Finder's Get Info › Open with › Change All.

### Photos library

Pictures in Apple's Photos library are browsed and converted without exporting them first. Nothing in
the library is ever changed, except a delete the person confirms in the system's own prompt.

- **Open from Photos… (File, ⇧⌘O, after Open Recent):** a sheet lists "Library", "Favorites",
  "Recents", then "Media Types" (the system's smart albums that hold pictures: Selfies, Portrait,
  Panoramas, Screenshots, Live Photos, Bursts, RAW, …, each under the name Photos gives it), then "My
  Albums" (the person's albums; albums inside folders show the folder path under the name). Hidden
  and Recently Deleted are never listed, nor are shared albums. Each row has the album's picture
  count, filled in off the main thread. ↑/↓ and typing a name select, Return or a double click
  opens the album in the window, Esc closes the sheet. It remembers the last album chosen.
- **Browsing an album** works like a folder: arrow keys, Home / End, Random Image, the grid (T),
  slideshow, Compare, zoom and the info panel. Order is the album's own; Library, Recents, Favorites
  and the media types are in date taken order, oldest first, as Photos shows them. Library, Recents
  and the media types open at the newest picture (the last), as Photos opens scrolled to the end;
  user albums and Favorites open at their first picture. Videos are left out; a Live Photo shows its
  still; an edited picture shows its current version. The title shows the picture's original file
  name ("IMG_1234.HEIC — 3 / 120"), the grid's title the album's name; the status bar shows the pixel
  size and the date taken instead of the file size.
- **Read-only:** Sort By, Rename, Move to Folder (F7), rotate and flip, Adjust Date Taken, Set as
  Desktop Picture, Follow New Files, Show in Finder and Open With are off for library pictures
  (changing them is an edit in Photos). Copy to Folder (F8), Save As, Copy (⌘C), Batch Convert… and
  the info panel's EXIF act on the current version's file, which Featherview fetches from Photos into
  its own cache folder (`~/Library/Caches/net.mynetx.featherview/Photos`, emptied at quit and at
  launch). Refresh (F5) reads the album again. Moving past the end of an album follows "Past the end
  of a folder", except that the folder chooser becomes Stop (an album has no neighbouring folders).
  Library albums are not listed in Open Recent.
- **Delete** (⌘⌫, ⌦) moves the picture to Photos' Recently Deleted, after the system's own
  confirmation (it replaces the "Confirm before moving to Trash" question for library pictures). In
  the grid it acts on the selection, in one prompt.
- **iCloud:** a picture whose original is only in iCloud shows Photos' local preview at once, and
  the status bar says "Downloading from iCloud…" until the original has arrived and replaced it.
  Without a connection the preview stays and the status bar says "Can't download IMG_1234.HEIC from
  iCloud."
- **Drops from Photos:** pictures dragged from the Photos app onto a viewer window open as a dropped
  selection: Photos hands over files, which land in a new folder in Featherview's cache folder
  (`…/Dropped/<n>`), and the window browses that folder. Onto the batch window's list they join the
  inputs. Onto the Dock icon, macOS hands over files as for any other app.
- **Permission only when used:** the system's Photos access prompt appears the first time Open from
  Photos… is chosen, never at launch, and nothing calls Photos before then (linking the framework costs
  launch nothing measurable). With access denied the sheet says "Featherview can't see your Photos
  library." and "Allow it in System Settings › Privacy & Security › Photos." with a button that opens
  that page. With limited access the sheet lists what the person shared, under "Library". Because
  releases are ad-hoc signed, macOS may ask again after an update (its permission is tied to the
  build); with Developer ID signing it would remember (see "Distribution").
- **Budgets:** as for folders (AGENTS.md): an album of 10,000 pictures shows its first picture in
  < 500 ms, prefetched next / previous ≈ 20 ms, not prefetched < 150 ms for local originals. Fit and
  grid pictures come from Photos' image manager at the size the screen or the cell needs, with the
  same 2-each-way prefetch and the same 8-image and thumbnail caches; zoom beyond fit decodes the
  original from the cache folder.
- **Not planned:** organising the library (albums, keywords, favourites), changing pictures in it,
  syncing edits back, Photos' "Edit With" round trip, shared albums and videos.

## Look

Featherview looks like a Mac app with a few touches of its own; the app icon (a warm feather on a
dark tile) carries the identity.

- Colour: controls, selection and focus use the app's feather accent (coral in dark, brown in light,
  never the system blue), Start and every default button included; text on the accent is graphite in
  dark and white in light. The feather gradient (#ffc766 to #ff7a59) appears only in the About
  window, the empty-window hint and the disk image.
- Type: the system font everywhere; tabular figures wherever numbers change in place (status strip,
  batch progress and log).
- Motion: browsing is instant (no crossfade). A zoom step animates in 120 ms, the info panel slides
  in 180 ms, resting bars fade out in 200 ms and back in 120 ms. With Reduce Motion the zoom step and
  the panel are plain cuts; the bars' fade (opacity only) stays.

## Batch window (B, ⌘B)

### Window

Two columns and a bottom bar, titled "Batch Convert":

- Images (leading, step 1): the input list with a small thumbnail, name, pixel size, file size
  and page count per file; files and folders can be dropped on it; add (menu: Add Files…, Add
  Folder…, Add Folder with Subfolders…, Use Viewer's Folder), remove, Sort and a menu with Move
  up/down, Save List… and Load List…. When empty it shows one prominent **Choose Folder…** button,
  with Add Files… and "or drop images here" beneath it.
- Settings (trailing) as numbered cards that are always there: **2 Format**, **3 Size**,
  **4 Name**. Below them **Add Step**, a menu of the eleven extra steps (Frames and Pages, Crop, Rotate and
  Flip, Colour, Filters, Canvas, Border, Text, Watermark, Tiles, Date Taken; steps already added are
  disabled in it).
  Picking one adds its card below the core cards, in the menu's order, opened; its ✕ removes it
  and turns the step off. An added step is on.
- One card is open at a time; opening one folds the others. A folded card is one line: its name
  and a summary in words ("JPEG · 85", "Longest side 2048", "trip-{n:3} · Out", "Brightness
  +10"). ⌘2, ⌘3 and ⌘4 open Format, Size and Name. Cards use the same grouped form as
  Settings (labels leading, controls trailing).
- Under the cards a live preview of the selected input (original and output side by side with
  their pixel sizes, small, rendered off the main thread, never blocking typing), the first
  output names, and one line naming the steps that are on in their processing order ("Applied:
  crop → size → watermark"). The preview keeps at least 160 pt; the cards scroll instead.
  When one input gives several files, the output caption reads "Output 800 × 450 · 4 files" (the size
  of each part; the first frame's for frames), Tiles draws the tile edges as thin lines on the output
  picture, and the names list shows each input's parts in order (the first five names in all).
- Bottom bar: Presets at the leading edge; **Convert N Images** (⌘↩) at the trailing edge.
- Running: the cards give way to one line with every card's summary, "n of N", a progress bar,
  the time left, and the image just written (name, pixel size, file size). Each input row shows
  its state (waiting, working, done with its (first) output name, failed). Pause/Resume and Stop replace
  the main button.
- Done: one sentence ("47 of 48 images converted in 1 minute, 12 seconds. 210 MB in, 96 MB out.
  Saved to ~/Desktop/Out."; "47 of 48 images converted into 530 files in …" whenever outputs outnumber
  converted inputs; MB out and Show in Finder count every part), then every failed file with its reason, Show in Finder and Copy
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
  is dropped silently. The Frames and Pages step writes a file per frame or page instead.
- `{part}` names the parts of an input that gives several files: frames and pages their number,
  zero-padded to the digits of the count (`01` … `12`); tiles `row-column`, each padded to the digits
  of rows / columns (`1-2`, `01-10`), rows top to bottom and columns left to right in the picture (never
  mirrored); both steps `frame-row-column` (`03-1-2`). A pattern without `{part}` gets `-{part}` appended
  when an input gives more than one file (`holiday-01.png`; when a name is shortened the part stays
  whole); an input that gives one file never gets it, and an explicit `{part}` then becomes `1`. The
  `{part}` button shows only while Frames and Pages or Tiles is on. `{n}` counts inputs: every part of
  one input shares it, and it advances only when the input succeeds. Clashes get " 2", " 3" per part
  (`holiday-01 2.png`); "Replace existing files" applies per part. The log line for such an input reads
  "loop.gif → loop-01.png … loop-12.png (12 files)".
- Name card: the rename pattern, then "Save to": **Next to the originals** (empty, the default),
  a chosen folder, with a "Next to the originals" button to go back while a folder is set
  (the reference viewer's button for the browsed folder), or **Photos library**: each output is
  added to Photos as a new picture (the rename pattern names its original file) and nothing stays
  on disk. Photos library asks for add-only access the first time a batch runs with it, which lets
  Featherview add pictures but never see the library; it offers only the formats Photos imports
  (JPEG, HEIC, PNG, TIFF, GIF; with any other format the choice is off and says "Photos can't
  import <format>."). An output Photos refuses fails its row ("Can't add holiday.png to Photos.").
  Pictures from the Photos library have no originals on disk: with them in the list, "Next to the
  originals" is off and Start asks for a folder or Photos library ("Choose where to save pictures
  from Photos."). `{folder}` in the output path stands
  for the input file's folder name.
  The safety and date options below sit in the same card.
- Rename pattern (always applied; `{name}` by default): `{name}` original name, `{n}` counter, `{n:3}` zero-padded counter, `{date}`
  date taken (YYYY-MM-DD, file date if missing). `/` and `:` become `-`. Empty pattern keeps the
  original name. The counter starts at 1 and advances only for files that succeed.
- The window shows the first output names live, without writing anything (the reference
  viewer's test-rename button).

### Per-image operations (applied in this order)

1. Frames and Pages (no settings: "Each frame of an animation and each page of a document becomes its
   own file."; summary "Every frame or page"): every frame of an animation (GIF, APNG, WebP, HEIC and
   AVIF sequences, ANI), full size and composited, or every page of a multi-page file (TIFF, PDF, DCX)
   becomes its own output, each through every later step, each a single-page file (TIFF "keep all
   pages" and PDF output then write one page). All frames, no range. A still gives one output, named as
   without the step. Splitting into frames or pages drops HDR (tiles of an HDR photo keep it).
2. Crop: fixed rectangle (x, y, width, height) from a chosen corner or the centre.
3. Resize: width and/or height, longest side, shortest side, megapixels, or percentage. Options:
   keep aspect ratio (default on), don't enlarge smaller images (default on), don't shrink
   larger images, DPI value.
4. Rotate left/right, flip horizontal/vertical.
5. Colour: greyscale, negative, auto-adjust colours, brightness, contrast, gamma, saturation,
   per-channel balance, sharpen, blur, reduce colour depth. Filters, each with one strength
   value: unsharp mask, noise reduction, sepia, colour temperature, auto levels (histogram
   stretch). No artistic filters.
6. Auto-crop uniform borders, canvas size, border, text overlay, watermark image:
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
7. Tiles: columns 1–100 and rows 1–100 (default 2 × 2), overlap in pixels (default 0; negative leaves
   gaps, "Negative values leave gaps"); summary "2 × 2" or "2 × 2, overlap 10 px". What the preview
   shows is what gets cut. All tiles have the same size: w = min(W, ⌈(W + (c − 1)·o) / c⌉) (under 1 px
   the input fails with "<name>: the tile settings leave no image"); tile i starts at
   round(i·(W − w) / (c − 1)) (0 for one column); the same for rows. So the first tile starts at 0, the
   last ends at W, and neighbours share about o pixels. A multi-page input without Frames and Pages
   gives tiles of page 1, with the "page 1 of 3" note; with both steps, tiles of every frame.
8. Date Taken ("Change:" Set to / Shift; default Shift by nothing, "No shift"; footnote "Changes the
   converted files, not the originals."): "Set to" one date and time ("Date taken:", with seconds, first
   filled from the first input's date taken, else its file date), or "Shift" Later / Earlier by days
   (0–3650), hours, minutes and seconds. It changes the outputs' date, never the originals'.
   - Re-encoded outputs get EXIF `DateTimeOriginal`, `DateTimeDigitized` and TIFF `DateTime`, also with
     the format's "keep metadata" off (ImageIO's formats and JPEG XL; WebP, QOI, PCX, PBM / PGM / PPM and
     PDF get only the file dates).
   - With Change format off and no other pixel step, Frames and Pages or Tiles, the output is the
     original's bytes with only the date changed (lossless) for JPEG, HEIC, TIFF and PSD; any other
     file fails with "Can't change the date taken of IMG_0412.gif". Set to without a date fails with
     "Choose a date for the Date Taken step".
   - `{date}` in the pattern and in the text overlay use the new date. The output's file dates
     (modified and created) follow the new date taken and win over "Keep file dates".
   - Shift without a date taken starts from the file's modification date, so the output gains an EXIF
     date. Dates are wall times as EXIF stores them; shifting is plain arithmetic on the wall time (no
     time zone, so no daylight-saving jumps). The file date is that wall time at EXIF
     `OffsetTimeOriginal` when present, else in the Mac's time zone. Known limit: TIFF loses
     `OffsetTimeOriginal` and `SubsecTimeOriginal` in the lossless rewrite.

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
- One input's outputs are one unit: each part is written to a hidden `.featherview-<id>.tmp` in the
  output folder as soon as it is made (one frame in memory per worker). If any part fails, the input
  fails with one sentence and its temp files are removed; if moving a part into place fails, the parts
  already moved for that input are removed again ("Can't save <name>"). Stop finishes inputs in flight.

## Settings (⌘,)

The menu calls it "Settings…", macOS's name since macOS 13; the single key P stays for people switching over.

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
- Full screen: overlay text (on, top leading corner, `{path} — {index} / {count}`; template with `{name}`, `{folder}`,
  `{path}` (full path, home as `~`), `{index}`, `{count}`, `{size}`, `{date}`); hide the pointer (on).
- Move / copy: the 14 destination slots; ask before each move / copy (off).
- Open with: up to 3 external apps, opened with ⌥1, ⌥2, ⌥3 on the current file.
- Formats: per-format defaults (see "Format options"), saved profiles.

## About window

Our own About window replaces the plain standard panel. Mac-like, one small
window, nothing to configure.

- The feather icon, "Featherview", version and build (`0.1.0 (1)`), the one-line description.
- Links: website, source code on GitHub, report a problem (the bug report form, as Help › Report a
  Bug…), all opening the browser.
- Last, a short note that Featherview is free and that a coffee helps pay the $99 a year Apple asks
  for notarization (so macOS stops warning on the first open), with a "Buy Us a Coffee" link to
  GitHub Sponsors (the same account as `.github/FUNDING.yml`).
- "Supported formats": two lists, read and write, built at runtime from ImageIO plus our own
  encoders (see "Formats"), with the macOS version they come from.
- "MIT License" and "Acknowledgements": the licence text of every bundled library (libwebp, jxrlib, libjxl with
  Highway, Brotli and skcms) and the credits for the place data (GeoNames, CC BY 4.0, simplified;
  Natural Earth, public domain), each in a scrollable sheet with clickable links. Copyright line.
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
    percentile; the first row is the bottom one; tile-compressed FITS can't be opened. ANI plays its
    frames at their largest size ("Animation"). PAM goes through ImageIO, which reads it
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
- Write (open-source encoder, per `AGENTS.md`): WebP (libwebp, BSD), JPEG XL (libjxl, BSD).
- JPEG XL is always written by libjxl, never ImageIO (macOS reads JPEG XL but writes none; should a
  later macOS add a writer it stays hidden, so options and output are the same on every version). Only
  the app links libjxl; the Finder extensions don't.
  - Colour: an RGB image in an ICC-based colour space is written in that space (with its profile;
    plain sRGB as JPEG XL's own sRGB, no profile bytes); grey, CMYK, indexed, extended-range and HDR
    (PQ / HLG) spaces are converted to sRGB. 8 bits per sample, or 16 when the image has more than 8
    (a 16-bit PNG or TIFF saved lossless stays lossless). SDR only: HDR output stays a HEIC / AVIF
    feature.
  - Alpha is written only when the image has it (premultiplied); an opaque image has three channels.
  - Metadata, with "keep metadata": the source's EXIF, TIFF, GPS and IPTC fields as XMP in one `xml `
    box, without orientation and pixel dimensions; no `Exif` box. Pixels are upright, the stored
    orientation is always 1. DPI isn't written (JPEG XL has no field for it).
  - Speed and memory: each encode uses libjxl's threads, and at most two JPEG XL encodes run at once (one
    12 MP encode needs about 550 MB). A 12 MP photo at quality 90, effort 7 takes about 1.4 s.
  - Lossless JPEG recompression (JPEG XL's JPEG transcoding) is not offered.
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
| JPEG XL | lossless (default off), quality 1–100 (default 90, visually lossless; never below libjxl's distance 0.1), effort 1–9 (default 7; "Higher is slower and makes smaller files"), keep metadata (default on, "Keep camera data, location and keywords") |
| WebP | preset photo (default) / picture / drawing / icon / text, lossless, quality 1–100 (default 75), effort 0–6 (default 4) |

After testing ImageIO on macOS 27: it can't write JPEG without chroma subsampling
(except at quality 100), lossless HEIC/AVIF, PNG compression levels or interlaced GIF, so those
options are not offered. ImageIO's GPU texture formats (KTX, KTX2, ASTC, PVR, ATX, DDS) and HEIC
sequences are not offered for writing; any other type a newer macOS adds appears automatically.

Orientation is always applied to the pixels and the tag reset to 1 (not an option). Options are
remembered per format and can be saved as named profiles.

### Animation

Animated GIF, PNG (APNG), WebP, HEIC and AVIF sequences, and Windows animated cursors (ANI), play
in the viewer. The first frame shows as fast as a still image; the rest follow. Converting (batch,
Save As, copy) uses the first frame.

- Which files: an ImageIO file with more than one frame whose type is GIF, PNG, WebP, HEIC sequence
  or AVIF sequence, and ANI. A multi-image HEIC that isn't a sequence and a multi-page TIFF are not
  animations. `.apng` files are listed and read as PNG.
- Playing starts on open and loops forever, whatever loop count the file asks for. Each newly shown
  file starts at frame 1, playing; pause isn't remembered across files.
- Delays: each frame's own delay as the file stores it (not ImageIO's rounded value); 10 ms or less
  counts as 100 ms, as in browsers. ANI: its per-step rates, else its header rate, in 1/60 s.
- G pauses and plays (Image › Pause Animation / Play Animation, disabled for stills). ⌥→ / ⌥← step
  one frame and pause; nothing past either end. The page menu items and toolbar buttons serve
  both, titled Next Frame / Previous Frame while an animation shows.
- Status bar: "6 frames" while playing, "frame 3 / 6" while paused. The title and the full-screen
  overlay don't change.
- The system's Accessibility › Motion › Play animated images, when off: animations open paused on
  frame 1, G still plays; a change applies at once. No setting of Featherview's own.
- Frames decode at the image's size on screen (fit, or the zoom's step); zooming keeps the frame
  shown. All frames stay in memory when they fit in 64 MiB, else only the frame shown and the next
  two; leaving the file drops them.
- A late frame is never skipped: it shows as soon as it is decoded, and its delay counts from then.
  Playback stops while the window is hidden or minimized and goes on from the same frame.

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

Every release builds the place data (Info panel, "Place names") fresh from GeoNames and Natural
Earth (`scripts/places.sh`), so it never goes stale; the file is not committed. A build without
network uses the last file in the local cache and says so; a build with no file at all ships without
place names (coordinates only).

## Updates

Featherview updates itself through Sparkle (MIT, sparkle-project.org): it finds a new version,
shows its release notes, downloads it and installs it when asked, then relaunches.

- Feed: `https://featherview.mynetx.net/appcast.xml`, Sparkle appcast format (RSS 2.0 with the
  `sparkle` namespace). Per `<item>`: `<title>`, `<sparkle:shortVersionString>` (e.g. 1.2.0),
  `<sparkle:version>` (build), `<sparkle:minimumSystemVersion>`, `<link>` (the release page),
  `<description>` (release notes, simple HTML), `<pubDate>`, and `<enclosure>` with the disk image's
  https URL, `length`, `type="application/x-apple-diskimage"` and `sparkle:edSignature`. The same file
  serves 0.10, which only tells about a new version and ignores the enclosure.
- Every download is checked against the EdDSA public key in Info.plist (`SUPublicEDKey`) before
  anything is installed; a download that fails the check is thrown away with an error. The private
  key lives only in the maintainer's Keychain.
- The request sends nothing about the person or their Mac beyond the HTTP request itself (Sparkle's
  system profile stays off).
- Automatic check: on by default, at most once a day, never in the first 10 s after launch (Sparkle
  starts then, so it costs launch nothing). Settings › Browsing › "Check for updates
  automatically" turns it off; someone who turned it off in 0.10 keeps it off. No "check
  automatically?" question on first launch.
- Check for Updates… (app menu) checks at once and always answers: the update window, "You're up to
  date", or an error.
- Update window: Sparkle's own (release notes, Install Update, Remind Me Later, Skip This Version),
  in Sparkle's languages; where it has none, English.
- Installing: when the person chooses Install and Relaunch, or else when Featherview quits. If their
  account can't write to the folder the app is in (a standard account and /Applications), macOS asks
  for an administrator's name and password.
- Homebrew: the cask declares `auto_updates true`, so `brew upgrade` leaves the update to Sparkle.

## App icon

The feather mark, `Resources/AppIcon.svg` (source of `AppIcon.icns` and the
website favicon). No cat imagery.

Document icon: files in the formats only Featherview reads (the types Featherview declares) show the
feather alone, without the app icon's tile, on the system's document page with the extension under
it, also when another app is their default. A default app's own document icon wins where it brings
one (GIMP for several of these formats). JFIF and APNG, which Preview reads too, keep the system's
icons.
