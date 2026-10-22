# Milestone 11: Viewer conveniences — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** The everyday Mac conveniences around the viewer: File › Open Recent (and the Dock menu),
Rename in the title (F2), View › Sort By, Share, Set as Desktop Picture, Window › Float on Top,
File › New from Clipboard (⌘N) and View › Follow New Files.

**Architecture:** Core gets four small pieces: the sort order (`SortOrder`, `ImageSort`: what each
key sorts by, read off the main thread, and the sort itself, pure), renaming (`FileRenamer`: name
rules and a rename that can never overwrite), the clipboard image and saving an image that has no
file (`ClipboardImage.image(from:)`, `ImageSaver.save(_ image:…)`), and folder watching
(`FolderWatch` on the folder's vnode, `Arrivals` for what arrived and when it is complete). The app
wires them into `ViewerModel` through extensions in their own files, so the main file only gains
stored properties and one-line hooks; recents, Share, desktop picture and Float on Top are the
system's own services (`NSDocumentController`, `ShareLink`, `NSWorkspace`, `NSWindow.level`).

**Tech Stack:** Swift 6, Foundation (`renamex_np`, `DispatchSource` file-system object source), ImageIO,
SwiftUI + AppKit (`NSDocumentController`, `ShareLink`, `NSWorkspace.setDesktopImageURL`, `NSWindow.level`,
`NSPasteboard`), Swift Testing. No new dependency.

**Spec:** `docs/roadmap.md` "Viewer conveniences (v2)" (the Mac form, which wins where it differs from
parity), `docs/parity.md` "Viewer conveniences" (the reference's behaviour), `docs/spec.md` "Viewer",
"Keys", "Toolbar", "Menu commands", "Mouse and trackpad", "Look", `docs/DESIGN.md`. The spec has no
section for these yet; Task 10 writes one from the Decisions below. Rules: `AGENTS.md`.

## Decisions (the roadmap leaves these to the plan; accepted by the maintainer)

1. **Open Recent** — File › Open Recent below Open…, the system's recent documents
   (`NSDocumentController.shared`), newest first, as many as System Settings › Desktop & Dock ›
   "Recent documents" allows (10 by default), then "Clear Menu". Items show the file or folder name;
   two items with the same name get " — <folder>" after it. An item whose file is gone is left out
   when the menu is built. What counts as opened: a file or folder opened with ⌘O / O, dropped on the
   window or the Dock icon, opened from Finder (Open With, double-click), chosen in Open Recent, or
   written by Save As. Not: browsing, the folder chooser's Return, Follow New Files. A renamed or
   moved file keeps its entry (the system stores bookmarks, which follow the file; see Spike facts).
   The Dock menu lists the same entries by itself (the system reads the same list); no code.
   Read after the first image is drawn, never on the launch path.
2. **Rename** — File › "Rename…  (F2)", F2, the context menu's Rename…, or a click on the file
   name in the window title turns the name in the toolbar's title into a text field (Preview's title
   rename, without its popover): the whole name with the part before the extension selected, as
   Finder does. Return or clicking elsewhere renames; Esc cancels. With the toolbar hidden or in
   full screen, F2 / Rename… show the same field in a small sheet ("Rename", Cancel / Rename) instead.
   - Unchanged or empty after trimming spaces: nothing happens.
   - Refused, message in the window's message box, field stays open while it has focus: a "/" or ":"
     or a control character; a leading "."; more than 255 characters (UTF-16 units); a name taken by another file
     ("“B.jpg” is already taken. Choose a different name."). Nothing is ever overwritten (the rename
     is `renamex_np(…, RENAME_EXCL)`); a name differing only in case renames.
   - A changed extension asks first, as Finder does ("Keep .jpg" default / "Use .png").
   - Sidecars (`.xmp`, `.aae`, `.thm`) follow when "Move sidecar files along" is on, under the new
     base name with their own extension. If any sidecar's new name is taken, nothing is renamed and the
     message names that sidecar.
   - Afterwards the title shows the new name, the list re-sorts in the current sort order, the picture
     stays on screen without a new decode, and the position updates. Disabled for a held (removed)
     image and an unsaved clipboard image. Queued behind rotations, moves and Trash like they are.
3. **Sort By** — View › Sort By: Name (Finder order, as today), Date Modified, Date Taken, Size,
   Kind, then Ascending / Descending; ticks on the current choices. **Global and remembered**
   (`AppSettings.sortKey`, `sortAscending`), default Name, Ascending: every viewer window re-sorts at
   once, and every folder opens in it. Changing it keeps the current image on screen and updates its
   position. Ties, and files whose value can't be read, fall back to name order, ascending; unreadable
   values go last in both directions. Date Taken is EXIF `DateTimeOriginal`, else the modification
   date (`MetadataReader.dateTaken`). Kind is the system's name for the extension's type
   ("JPEG image"), the extension in capitals when it has none.
   - Name, Date Modified, Size, Kind need no file contents (directory and `stat` data): a folder opens
     on the first image in that order, inside the 500 ms budget.
   - Date Taken reads every file's header, too slow for the open budget (Spike facts): the folder
     opens in name order, its first image by name shows at once, the dates are read off the main
     thread at utility priority, then the list re-sorts with the image shown kept. Nothing blocks.
   - Not taken: "no sort" (the directory's own order means nothing on APFS) and the reference's
     plain (non-Finder) name sort.
4. **Share** — a toolbar button (`square.and.arrow.up`, tooltip "Share", between Info and Move to
   Trash, in the default set), File › Share (a submenu of the system's services, after Save As… and
   Rename…) and Share in the context menu: the system's share menu for the current file, which also
   covers Mail. Disabled for a held image and the clipboard image.
5. **Set as Desktop Picture** — Image › "Set as Desktop Picture" and in the context menu: the current
   file on **every screen** (Finder's Set Desktop Picture does one; people with two screens expect
   both to change), fill mode (`imageScaling: .scaleProportionallyUpOrDown`, `allowClipping: true`),
   no confirmation (System Settings undoes it). The file is used where it is. Only for files the
   system itself can show (ImageIO types; not Featherview's own formats nor PDF), else disabled.
   Failure: "Couldn't set <name> as the desktop picture".
6. **Float on Top** — Window › "Float on Top" (ticked while on), per window (`NSWindow.level =
   .floating`), not remembered across launches, as QuickTime Player. Disabled in full screen.
7. **New from Clipboard** — File › "New from Clipboard" ⌘N (Preview's name and shortcut), first in the
   File menu. It shows in the window in use (the main one when none is), covering its list: the
   window's list stays behind it, unchanged.
   - What it takes: a copied image file Featherview reads (Finder's Copy) opens that file, as ⌘O
     would; otherwise the first image type on the clipboard ImageIO decodes (PNG, TIFF, JPEG, HEIC, …),
     full size, orientation applied. Disabled when neither is there (checked when the app becomes
     active and after Featherview's own ⌘C).
   - Shown as an unsaved image: title "Untitled" with the window's edited dot, status strip with
     pixel size and zoom only. Zoom, full screen, ⌘C and Save As work; everything acting on a file
     (rotate, Trash, F7 / F8, Rename, Share, Desktop Picture, Info, Show in Finder, Open With) is
     disabled because the covered list has no current file.
   - Save As (S, ⇧⌘S) writes it in any writable format, with "Untitled" as the name and the list's
     folder (else Pictures) as the place, then shows the saved file in its folder, as Save As does.
   - Leaving it asks first (sheet, the Mac's wording): "Do you want to save the image from the
     clipboard?" / "If you don't save it, it's gone." — Save… (default), Don't Save, Cancel. Asked for
     ← → ↑ ↓ Space ⌫ Page Up / Down Home End, ⌘O / O, a drop, a Finder file sent to this window, Open
     Recent, ⌘N again, closing the window and ⌘Q. Save… saves and then carries on with what was asked
     (without opening the saved file). After leaving, the image shown before the paste shows again,
     whatever key was pressed (Home / End go to the first / last).
8. **Follow New Files** — View › "Follow New Files" (ticked while on), per window, off by default, not
   remembered; disabled without a folder. While on, the window watches its folder: each change
   rescans the names (as opening does, ≈ 11 ms per 10,000), adds new images to the list in sort order,
   drops vanished ones, and shows the newest arrival (latest modification date) once its size has
   stayed the same for 250 ms (a file still being copied or exported isn't shown half-written; given
   up after 30 s). A burst of files shows its newest once. Arrivals don't interrupt a rename field, the
   folder chooser, the F7 / F8 panel or an unsaved clipboard image: the list takes them, the window
   stays. A current file deleted elsewhere stays on screen, held, until the next key. Opening another
   folder moves the watch there; the folder itself renamed or deleted turns following off. There is
   **no** folder watching today (`ViewerModel` has no file-change handling): `FolderWatch` is new, and
   it runs only while following, so launch and browsing pay nothing.

## Spike facts (macOS 27, own test files; don't re-measure)

- `NSDocumentController.shared.noteNewRecentDocumentURL` works in an app without `NSDocument`; it
  accepted a JPEG, a folder, a `.qoi` and even a `.swift` file with only `public.image` declared (no type
  check). `recentDocumentURLs` is newest first; `maximumRecentDocumentCount` was 10. The list lands in
  `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/<bundle id>.sfl4`
  (what the Dock reads). After the file was renamed, the entry showed the new name (bookmark).
  `clearRecentDocuments(nil)` empties it.
- Sort values for 10,000 files (small JPEGs, M1 Pro): `resourceValues([.contentModificationDateKey,
  .fileSizeKey])` 89 ms cold, 14 ms warm; `stat` 22 ms; kind through `UTType(filenameExtension:)
  .localizedDescription` cached per extension 5–7 ms. EXIF date (`CGImageSourceCopyPropertiesAtIndex`)
  0.12 ms per tiny file with a warm cache: ≥ 1.2 s per 10,000, much more for real files on a cold disk.
- `renamex_np(from, to, RENAME_EXCL)`: a case-only rename (`CASE.jpg` → `Case.jpg`) succeeds on APFS
  (case-insensitive); onto another existing file it fails with `EEXIST`, atomically.
  `FileManager.moveItem` also refuses an existing target (error 516) but checks before renaming (a race).
- `DispatchSource.makeFileSystemObjectSource` on the folder (`open(path, O_EVTONLY)`): `.write` fires for
  a file added, an atomic write (temp + rename, twice), a rename inside the folder and a delete; nothing
  for appending to an existing file in place. Renaming the folder itself gives `.rename`.

## Where this meets parallel milestones (touch points; keep churn small)

- **`ViewerModel.swift`** — M9 (player in `show()`, `nextPage` / `previousPage`, `toggleAnimation()`,
  `availability.hasPages`), M13 (`isGrid`, grid decodes, `trash(_ urls:)`, `transfer` for a selection,
  `availability.canShowGrid`). This milestone puts its methods in new files
  (`ViewerModel+Sort.swift`, `+Recents.swift`, `+Rename.swift`, `+Clipboard.swift`, `+Follow.swift`);
  `ViewerModel.swift` gets only: one stored-property block after `slots`; `private` / `private(set)`
  widened to internal on `list`, `image`, `fileInfo`, `cache`, `fullSizeCache`, `ready`, `knownInfo`,
  `rotateTask`, `openTask` (the extensions use them; one word per line); the sort in `open(_:)` (Task 5);
  a `remember:` parameter on `open(_:)` (Task 6); one guard line at the top of `next`, `previous`,
  `first`, `last`, `open`, `setZoom` (Task 8); `hasPicture` in `Availability` (Task 8).
- **`ViewerView.swift`** — M9 (G key, Image menu items), M13 (grid, T key, View menu items, zoom
  titles). Here: F2 in `handle` next to F7 / F8; one line per menu insertion, the menus themselves in a
  new `Sources/Featherview/Viewer/ConvenienceMenus.swift` (`RecentMenu`, `SortMenu`, `ShareMenu`,
  `ClipboardCommand`); context menu items; the `@AppStorage` sort observers.
- **`ViewerToolbar.swift`** — M9 tooltips, M13 Thumbnails toggle. Here: one `share` item and the
  `WindowTitle` rename field.
- **`ImageList.swift`** — M13 Task 2 adds `select(_ url: URL) -> Bool`. Task 1 here needs the same
  method: if M13's wave A hasn't landed, Task 1 adds it with M13's signature and tests
  (`selectMakesCurrent`, `selectUnknownIsFalse`); whichever lands second keeps one copy.
- **`AppSettings.swift`** — M13 adds `thumbnailSize`; Task 1 adds `sortKey`, `sortAscending` (separate lines).
- **M13's grid** shows `model.list.urls` in their order and reloads on every list change, so Sort By,
  Rename and Follow New Files reach it with no grid code. `ImageSort` (Task 1) is the Core interface
  should the grid ever sort on its own: `ImageSort.sorted(_:by:values:)` with `SortOrder.stored()`.
  In the grid, Rename, Set as Desktop Picture and Share act on nothing (disabled) until a later plan
  says otherwise; whichever milestone lands second adds `!isGrid` to their availability.
- **M10** (document icon) touches only `Info.plist` and assets: no overlap.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Performance budgets in `AGENTS.md` hold: cold launch < 410 ms (no recents read, no watcher, no
  pasteboard read on the launch path), a 10,000-file folder < 500 ms to first image in every sort order
  (Date Taken by deferring), prefetched next / previous ≈ 20 ms (no work added to `show()`'s path).
  "Never touch file contents while scanning a folder" holds: only Date Taken reads headers, after the
  scan, off the main thread.
- Never lose user data: rename never overwrites (`RENAME_EXCL`); an unsaved clipboard image is never
  dropped without asking; Save As writes through a temp file and swaps it in.
- Colours, radii, metrics, durations only from `Theme.swift`; leading/trailing, never left/right.
- Every user-facing string translatable, whole sentences with placeholders. None of the new strings
  carries a count, so no plural variations are needed; if one gets a count, it gets plural variations.
  New strings get all 30 languages (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10): the shared steps").
- Test images come from `Fixtures`, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- `img.jpg` renamed to `IMG.jpg` on a case-insensitive volume: renames, never "already taken"; a clash
  with another file (or a sidecar's name) renames nothing. Pinned in Task 2 (`caseOnlyRenameWorks`,
  `takenNameChangesNothing`, `takenSidecarNameChangesNothing`).
- Date Taken on a 10,000-file folder: the first image shows within the open budget, the list re-sorts
  later with the picture kept and no visible jump. Pinned in Task 1 (`readsFileHeadersOnlyForDateTaken`)
  and Task 5 (open uses name order for it), measured in Task 10.
- Every way out of an unsaved clipboard image asks (keys, ⌘O, drop, Finder file, Open Recent, ⌘N,
  close, ⌘Q), and no file action reaches the covered list's file meanwhile. Pinned in Task 8 (the
  covered list is empty, so file actions find no current file; guards in the six entry points),
  checked on screen in Task 10.
- A file still being written (big copy, camera export) under Follow New Files: shown once complete,
  never as "Can't open"; 50 files at once show the newest once and leave no decodes piling up. Pinned
  in Task 4 (`settledWaitsForGrowth`, `newestByModificationDate`, `burstReportsFew`) and Task 9
  (one arrival shown per rescan, through `show()`'s refocus).
- A rename, sort or arrival while a rotation, move or Trash is still running: the list never brings a
  trashed file back and never loses the renamed one. Pinned in Task 1 (`reorderKeepsHeld…`), Task 7
  and Task 9 (queued behind `rotateTask` and `openTask`, like Trash).

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2, 3, 4 | independent Core pieces (sort; rename; clipboard and saving; folder watching) |
| B | 5, 6, 8 | Sort By in the viewer (uses 1); recents, Share, desktop picture, Float on Top (no Core); New from Clipboard (uses 3) |
| C | 7, 9 | Rename (uses 2 and 5's re-sort); Follow New Files (uses 4, 5's re-sort, 8's unsaved state) |
| D | 10 (main session) | screen check, budgets, docs |

---

### Task 1: Sort order in Core

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/ImageSort.swift`
- Modify: `Sources/FeatherviewCore/Viewer/ImageList.swift` (`reorder`, `select` if M13 hasn't added it),
  `Sources/FeatherviewCore/App/AppSettings.swift` (`sortKey` default "name", `sortAscending` default true,
  both registered)
- Test: `Tests/FeatherviewCoreTests/Viewer/ImageSortTests.swift`, `Viewer/ImageListTests.swift`,
  `App/AppSettingsTests.swift`

**Interfaces:**
- Produces:
  - `public enum SortKey: String, CaseIterable, Sendable { case name, dateModified, dateTaken, size, kind }`
  - `public struct SortOrder: Equatable, Sendable { public var key: SortKey; public var ascending: Bool }`
    with `public static let finder` (name, ascending), `public static func stored(in: UserDefaults = .standard) -> SortOrder`
    (unknown raw value → `.name`), `public func store(in: UserDefaults = .standard)`,
    `public var readsFileHeaders: Bool` (true only for `.dateTaken`).
  - `public enum SortValue: Equatable, Sendable { case date(Date), bytes(Int), text(String) }`
  - `public enum ImageSort`:
    - `static func values(of urls: [URL], key: SortKey) -> [URL: SortValue]` — reads the disk, call off
      the main thread. `.name` → `[:]`; `.dateModified` / `.size` → `resourceValues`; `.kind` →
      `UTType(filenameExtension:)?.localizedDescription ?? ext.uppercased()`, looked up once per
      lowercased extension; `.dateTaken` → `MetadataReader.dateTaken(of:)`. A file it can't read has no entry.
    - `static func sorted(_ urls: [URL], by order: SortOrder, values: [URL: SortValue]) -> [URL]` —
      `.name`: `FolderScanner.inFinderOrder`, reversed when descending. Others: by value (dates and
      bytes numerically, text with `localizedStandardCompare`), reversed when descending; missing values
      last in both directions; ties in Finder name order ascending in both directions. Keys extracted
      once, not in the comparator (the scanner's 190 ms lesson).
    - `static func first(_ urls: [URL], by order: SortOrder, values: [URL: SortValue]) -> URL?` — the
      first of `sorted`, in one pass (`FolderScanner.firstInFinderOrder` for name ascending).
  - `ImageList.reorder(_ urls: [URL])` — takes `urls` as the new list. The current image stays current
    (index moves to it); a held image stays held with `index` on the image that followed it if still
    listed (else clamped); a current image missing from `urls` becomes held (it stays on screen until the
    next key, as with "show the next image" off).
  - `ImageList.select(_ url: URL) -> Bool` (M13's signature; see touch points).

- [ ] **Step 1: Write the failing tests** in `ImageSortTests`:
  `nameIsFinderOrder` ([img10, img2, Img1] → [Img1, img2, img10]); `nameDescendingReverses`;
  `dateModifiedOldestFirst` (values injected); `tiesFallBackToNameAscending` (equal dates, ascending
  and descending → a before b both times); `missingValuesSortLast` (ascending and descending);
  `sizeAndKindOrder`; `valuesReadModificationDateAndSize` (temp files, `setAttributes` with
  `.modificationDate`); `kindIsPerExtensionIgnoringCase` (`a.jpg`, `b.JPG` same text);
  `dateTakenPrefersExif` (`Fixtures.writeImage` with `[kCGImagePropertyExifDictionary:
  [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05"]]` and a newer mtime → the EXIF date;
  a PNG without EXIF → its mtime); `firstMatchesSorted` (200 shuffled names × every key and direction);
  `readsFileHeadersOnlyForDateTaken`; `storedOrderRoundTripsAndDefaultsToName` (fresh suite → `.finder`;
  `sortKey` "bogus" → `.name`).
  In `ImageListTests`: `reorderKeepsCurrent` (current c at 2 → reordered [c, a, b] → index 0, current c);
  `reorderKeepsHeldAndItsNext` (hold b in [a, b, c] → reorder [c, a] → still holding b, `next()` shows the
  image that followed, c); `reorderMakesMissingCurrentHeld` (current b, reorder [a, c] → `isHolding`,
  current b; `next()` → c); `reorderToEmpty`; `selectMakesCurrent`, `selectUnknownIsFalse` (if added here).
- [ ] **Step 2: Run** `swift test --filter "ImageSortTests|ImageListTests|AppSettingsTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter plus `FolderScannerTests|MetadataReaderTests` → PASS.
- [ ] **Step 5: Commit** `feat: sort order for the viewer's list (name, dates, size, kind)`

---

### Task 2: Renaming in Core

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/FileRenamer.swift`
- Modify: `Sources/FeatherviewCore/Viewer/FileInfo.swift` (`moved(to:)`), `Resources/Localizable.xcstrings`
- Test: `Tests/FeatherviewCoreTests/Viewer/FileRenamerTests.swift`, `FileInfoTests.swift`

**Interfaces:**
- Produces:
  - `public enum RenameProblem: Error, Equatable { case empty, invalidCharacter, hidden, tooLong, taken(String) }`
    with `public var message: String?` (`String(localized:)`; nil for `.empty`, which callers treat as cancel):
    invalidCharacter "A name can't contain “/” or “:”."; hidden "A name can't start with “.”: the file
    would be hidden."; tooLong "That name is too long."; taken(name) "“\(name)” is already taken. Choose a
    different name."
  - `public enum FileRenamer`:
    - `static func check(_ name: String) -> RenameProblem?` — on the name trimmed of whitespace and
      newlines: empty; contains "/", ":" or a control character; starts with "."; > 255 UTF-16 units.
    - `static func trimmed(_ name: String) -> String`
    - `static func stemRange(of name: String) -> NSRange` — UTF-16 range of the part before the last
      "."; the whole name when there is no "." after the first character.
    - `static func extensionChange(from file: URL, to name: String) -> (old: String, new: String)?` —
      nil when the extensions match ignoring case.
    - `@discardableResult static func rename(_ file: URL, to name: String, sidecars: [URL]) throws -> URL`
      — same folder. Checks first that no target (image or sidecar, "<new stem>.<sidecar ext>") is taken
      by another item (a case-only change of the same item isn't taken: compare
      `fileResourceIdentifierKey`, as `FileMover.sameItem` does); throws `RenameProblem.taken(<that
      name>)` and changes nothing. Then `renamex_np(old, new, RENAME_EXCL)` for the image (an `EEXIST`
      race → `.taken`), then each sidecar the same way, best effort (`shortcut:` comment, as FileMover's).
      A symlink renames the link, not its target. Returns the new URL; the same URL when the name is unchanged.
  - `public func FileInfo.moved(to url: URL) -> FileInfo` — same values, new URL (the picture stays on
    screen after a rename without a new read).

- [ ] **Step 1: Write the failing tests:** `renamesAndKeepsContent`; `caseOnlyRenameWorks`
  (`img.jpg` → `IMG.jpg`: listing shows `IMG.jpg`, bytes equal); `takenNameChangesNothing` (a.jpg →
  b.jpg with b.jpg present → `.taken("b.jpg")`, both files untouched); `takenSidecarNameChangesNothing`
  (IMG_1.jpg + IMG_1.xmp → B with B.xmp present → `.taken("B.xmp")`, IMG_1.jpg and IMG_1.xmp still
  there); `sidecarsFollowWithTheirExtension` (IMG_1.JPG + IMG_1.xmp + img_1.AAE → B.JPG, B.xmp, B.AAE);
  `unchangedNameDoesNothing`; `symlinkRenamesTheLink`; `checkRejects` ("", "  ", "a/b", "a:b", "a\u{7}b",
  ".x", 256 × "a" → each problem; "ü.jpg", "a b.jpg" → nil); `stemRange` ("IMG_1.jpg" → 0,5;
  "a.tar.gz" → 0,5; ".hidden" → 0,7; "noext" → 0,5; "📷.jpg" → 0,2); `extensionChange` (a.jpg → b.JPG nil;
  a.jpg → a.png ("jpg", "png"); a.jpg → a ("jpg", "")); `messagesUnderEnglish`; `movedKeepsValues` in
  `FileInfoTests`.
- [ ] **Step 2: Run** `swift test --filter "FileRenamerTests|FileInfoTests"` → FAIL.
- [ ] **Step 3: Implement;** `scripts/strings.sh`; the four messages in all 30 languages (shared steps).
- [ ] **Step 4: Run** `swift test --filter "FileRenamerTests|FileInfoTests|FileMoverTests|StringCatalogTests"` → PASS.
- [ ] **Step 5: Commit** `feat: rename files without ever overwriting, sidecars along`

---

### Task 3: Clipboard image, saving an image without a file, desktop formats

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/ClipboardImage.swift`, `ImageSaver.swift`, `ImageFormats.swift`,
  `Sources/FeatherviewCore/Viewer/StatusLine.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/ClipboardImageTests.swift`, `Imaging/ImageSaverTests.swift`
  (new), `Viewer/StatusLineTests.swift`, `Imaging/OutputFormatTests.swift` (`desktopCanShow`)

**Interfaces:**
- Produces:
  - `public static func ClipboardImage.image(from data: Data) -> CGImage?` — page 0, full size, EXIF
    orientation applied (`CGImageSourceCreateThumbnailAtIndex` with `…FromImageAlways`,
    `…WithTransform` and max pixel size = the longest side of `CGImageSourceCopyPropertiesAtIndex`'s
    size); nil for empty or undecodable data.
  - `public static func ClipboardImage.preferredType(_ types: [String]) -> String?` — the first type that
    conforms to `public.image` and that ImageIO decodes, in the clipboard's order (its producer's
    preference). File URLs are the app's business (it checks them first).
  - `public static func ImageSaver.save(_ image: CGImage, to destination: URL, as format: OutputFormat,
    options: FormatOptions) throws` — `ImageEncoder.encode([image], as:, options:)` without metadata, then
    the same temp-file-and-swap as `save(_ source: URL, …)`; both share one private
    `write(_ data: Data, to destination: URL) throws` (the existing body: resolve links, refuse a folder,
    temp file next to it, `replaceItemAt` or move).
  - `public static func StatusLine.unsaved(pixelSize: CGSize, zoomPercent: Int?) -> StatusLine` — the size
    and zoom fields only, formatted as `make` does.
  - `public static func ImageFormats.desktopCanShow(_ url: URL) -> Bool` — `isDecodable` and not an own
    format (`OwnDecoders.format(for:) == nil`) and not PDF.

- [ ] **Step 1: Write the failing tests:** `pngDataDecodes`, `tiffDataDecodes` (encode a fixture
  `CGImage` to data in memory), `jpegOrientationApplied` (4 × 2 JPEG data with orientation 6 → 2 × 4),
  `garbageAndEmptyAreNil`, `preferredTypeSkipsNonImages` (["public.utf8-plain-text", "public.png"] →
  png; ["public.file-url"] → nil; ["com.adobe.pdf", "public.tiff"] → tiff), `saveImageWritesPNG`
  (decodes back to the same size), `saveImageLeavesNoTempFile`, `saveImageRefusesAFolder`,
  `saveImageReplacesExisting` (existing file replaced only by a complete one: content differs after),
  `unsavedStatusLine` (["1,200 × 800", "50%"] under `en`), `desktopCanShow` (jpg, heic, png true; qoi,
  xcf, pdf false).
- [ ] **Step 2: Run** `swift test --filter "ClipboardImageTests|ImageSaverTests|StatusLineTests|OutputFormatTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter plus `OutputFormatTests` → PASS.
- [ ] **Step 5: Commit** `feat: decode clipboard images and save images that have no file`

---

### Task 4: Folder watching in Core

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/FolderWatch.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/FolderWatchTests.swift`

**Interfaces:**
- Produces:
  - `public final class FolderWatch: Sendable` —
    `public init?(folder: URL, quiet: Duration = .milliseconds(200), onChange: @escaping @Sendable () -> Void,
    onGone: @escaping @Sendable () -> Void)` (nil when the folder can't be opened); `public func cancel()`
    (idempotent; no callback after it returns). A `DispatchSource` file-system object source on
    `open(path, O_EVTONLY)` with `[.write, .delete, .rename]` on its own serial queue: `.write` reports
    `onChange` once the folder has been quiet for `quiet` (a burst is one report); `.delete` / `.rename`
    report `onGone` and cancel. State under an `OSAllocatedUnfairLock`. The fd closes in the cancel handler.
    `shortcut:` network volumes don't report remote changes to vnode sources, poll there if people follow
    folders on servers.
  - `public enum Arrivals`:
    - `static func diff(listed: [URL], scanned: [URL]) -> (added: [URL], removed: [URL])` — by URL, in
      `scanned` / `listed` order.
    - `static func newest(_ added: [URL], modified: (URL) -> Date?) -> URL?` — latest date; ties and
      missing dates by Finder name order, last wins; nil when empty.
    - `static func settled(_ url: URL, interval: Duration = .milliseconds(250), timeout: Duration =
      .seconds(30)) async -> Bool` — true once the file's size is non-zero and unchanged between two reads
      `interval` apart; false at `timeout`, when the file is gone, or when the task is cancelled.

- [ ] **Step 1: Write the failing tests:** `addingAFileReports` (write a file → `onChange` within 1 s, via
  an `AsyncStream` with a timeout); `burstReportsFew` (50 files written in a loop → 1 or 2 reports);
  `cancelStopsReports` (cancel, write → nothing within 600 ms); `folderRenamedReportsGone`;
  `missingFolderIsNil`; `diffAddedRemoved`; `newestByModificationDate`; `newestTieByName`;
  `newestOfNoneIsNil`; `settledTrueForCompleteFile`; `settledWaitsForGrowth` (write, append again after
  150 ms from a task → true, and not before the append); `settledFalseForEmptyFileAtTimeout` (timeout
  300 ms); `settledFalseWhenFileVanishes`.
- [ ] **Step 2: Run** `swift test --filter FolderWatchTests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter FolderWatchTests` three times in a row → PASS each time (no flake).
- [ ] **Step 5: Commit** `feat: watch a folder for new images and tell when they are complete`

---

### Task 5: View › Sort By in the viewer

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Sort.swift`, `Sources/Featherview/Viewer/ConvenienceMenus.swift` (`SortMenu`)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (stored properties, access widening, the sort in
  `open(_:)`), `ViewerView.swift` (View menu line, `@AppStorage` observers), `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 1 holds the logic); `swift build`, Task 10 on screen.

**Interfaces:**
- Consumes: `SortOrder`, `ImageSort`, `ImageList.reorder` (Task 1).
- Produces (Tasks 7 and 9 use these):
  - `ViewerModel.sortValues: [URL: SortValue]` (for the open folder and the stored key; emptied by `open`).
  - `func applySortOrder()` — reads `SortOrder.stored()`; queued behind `openTask`; reads missing values off
    the main thread (`.userInitiated`, `.utility` for Date Taken), then `relist(_:)`.
  - `func relist(_ urls: [URL])` — `list.reorder(ImageSort.sorted(urls, by: .stored(), values: sortValues))`,
    then `focusDecodes()` and prefetches the new neighbours at fit (as `becameActive()` does); never calls
    `show()` when the current image is unchanged.
  - `func readSortValues(for urls: [URL]) async` — reads and stores values for `urls` (new or renamed files).

Rules:
- `open(_:)`: the order is read on the main actor before `prepare`. In `prepare`, a folder's first image is
  `ImageSort.first(urls, by: order, values:)` with values read there when `!order.readsFileHeaders` (name
  needs none); for Date Taken, name order. The list is `ImageSort.sorted` the same way (replacing
  `FolderScanner.inFinderOrder`; a file's scan passes `sorted: false`). After the list is set, Date Taken
  starts `sortTask` (`.utility`, cancelled by the next `open`) that reads all values and calls `relist`.
- `SortMenu`: `Menu("Sort By")` with an inline `Picker` over `SortKey` (titles "Name", "Date Modified",
  "Date Taken", "Size", "Kind"), a `Divider`, an inline `Picker` "Ascending" / "Descending", both bound to
  `@AppStorage(AppSettings.sortKey.key)` / `sortAscending`. Placed after the zoom group in the View menu,
  after a `Divider`. Enabled without a window too (it is a setting).
- `ViewerView`: `.onChange(of: sortKey)` and `.onChange(of: sortAscending)` → `model.applySortOrder()`, so
  every open window re-sorts.

- [ ] **Step 1: Implement;** `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `swift run -c release featherview-bench corpus /tmp/fv` then
  `swift run -c release featherview-bench browse /tmp/fv/browse --interval-ms 300` → unchanged against
  `main` (the browse path is untouched).
- [ ] **Step 3:** `scripts/strings.sh`; the new titles in all 30 languages; `swift test` → all PASS.
- [ ] **Step 4: Commit** `feat: View › Sort By for the viewer's list, kept for every window`

---

### Task 6: Open Recent, Share, Set as Desktop Picture, Float on Top

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Recents.swift` (recents, desktop picture, floating)
- Modify: `Sources/Featherview/Viewer/ConvenienceMenus.swift` (`RecentMenu`, `ShareMenu`),
  `ViewerModel.swift` (`open(_:remember:)`, `chooserOpen` passes `remember: false`; `isFloating`),
  `ViewerView.swift` (File, Image and Window menu lines; context menu), `ViewerToolbar.swift` (`share`
  item, `ShareButton` view), `Sources/Featherview/FeatherviewApp.swift` (load recents after the first
  image), `Resources/Localizable.xcstrings`
- Test: none new in Core; Task 10 on screen.

**Interfaces:**
- Produces:
  - `@MainActor @Observable final class RecentFiles { static let shared; private(set) var urls: [URL];
    func note(_ url: URL); func clear(); func reload() }` — wraps `NSDocumentController.shared`
    (`noteNewRecentDocumentURL`, `recentDocumentURLs`, `clearRecentDocuments`); `reload()` keeps only
    existing items. First `reload()` after the first image is drawn (`ViewerModel.afterFrame`, where
    `DefaultViewerOffer.showOnce` waits), then on `NSApplication.didBecomeActiveNotification` and after
    each `note` / `clear`.
  - `ViewerModel.open(_ url: URL, remember: Bool = true)` — notes `url` in `RecentFiles` when `remember`.
  - `ViewerModel.setDesktopPicture()` — `NSWorkspace.shared.setDesktopImageURL(url, for:, options:)` for
    every `NSScreen.screens`, options of Decision 5, on the main actor (the call only records the choice);
    error → `errorMessage = String(localized: "Couldn't set
    \(name) as the desktop picture")`.
  - `ViewerModel.isFloating: Bool` — `didSet` sets `window?.level` to `.floating` / `.normal`.
  - `Availability.canSetDesktop` = `canChangeFile && ImageFormats.desktopCanShow(current)`, computed in
    `updateAvailability` (only on flips, as the rest).

Rules:
- `RecentMenu`: `Menu("Open Recent")` after Open…: one `Button` per URL (display name, " — <folder name>"
  for duplicate names) → `ViewerModel.lastActive.current.open(url)`; `Divider`; "Clear Menu" (disabled
  when empty). Folders opened directly are listed too (Decision 1).
- Share: `ShareButton` is its own view reading `model.list.current` inside its body (the toolbar's content
  must not read per-image state, see `ViewerToolbar`'s comment); `ShareLink(item: url)` with label
  "Share", `square.and.arrow.up`, `.help("Share")`, disabled with `!availability.canChangeFile`. Toolbar
  item id `share` between `info` and `trash`. File menu `ShareMenu`: `ShareLink(item:)` after Rename…'s
  place, in the `CommandGroup(after: .newItem)` after Save As…, preceded by a `Divider`. Context menu:
  "Share" (`ShareLink`), "Set as Desktop Picture".
- Image menu: "Set as Desktop Picture" after Open With, disabled by `canSetDesktop`.
- Window menu: `CommandGroup(before: .windowList) { Toggle("Float on Top", isOn: …) }` bound to the
  focused model's `isFloating`, disabled with no model or in full screen.
- Dock menu: no code; Task 10 checks it lists the recents.

- [ ] **Step 1: Implement;** `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; new titles ("Open Recent", "Clear Menu", "Share", "Set as
  Desktop Picture", "Float on Top", the error) in all 30 languages; `swift test` → all PASS. The
  behaviour needs a window: Task 10 checks it.
- [ ] **Step 3: Commit** `feat: Open Recent, Share, Set as Desktop Picture and Float on Top`

---

### Task 7: Rename in the title (F2)

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Rename.swift`, `Sources/Featherview/Viewer/RenameField.swift`
  (`RenameField: NSViewRepresentable` over `NSTextField`, `RenameSheet` view)
- Modify: `ViewerToolbar.swift` (`WindowTitle` shows the field while renaming; a click on the name starts
  it), `ViewerView.swift` (F2 in `handle`, File menu item, context menu item, the sheet),
  `ViewerModel.swift` (stored properties), `Sources/Featherview/Design/Theme.swift` (field tokens if any),
  `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 2 holds the rules); Task 10 on screen.

**Interfaces:**
- Consumes: `FileRenamer`, `RenameProblem`, `FileInfo.moved(to:)` (Task 2); `relist(_:)`,
  `readSortValues(for:)` (Task 5); `Sidecars.files`, `AppSettings.moveSidecars` (existing).
- Produces:
  - `ViewerModel.renaming: Bool` (the field shows), `func beginRename()` (guards `canChangeFile`),
    `func cancelRename()`, `func commitRename(_ name: String) async -> Bool` (false keeps the field open).
  - `RenameField(text:, onCommit:, onCancel:)` — selects `FileRenamer.stemRange` when it gains focus;
    Return and losing focus commit, Esc (`cancelOperation`) cancels; title font and colours from `Theme`
    (`Theme.windowTitle`, `labelPrimary`), its width that of the name.

Rules:
- `commitRename`: `FileRenamer.trimmed`; unchanged or `.empty` → cancel; `check` problem → `errorMessage =
  problem.message`, return false. `extensionChange` → `NSAlert` sheet: "Are you sure you want to change
  the extension from “.\(old)” to “.\(new)”?", informative "The image may then open in another app, or
  not at all.", buttons "Keep .\(old)" (default) / "Use .\(new)"; Keep puts the old extension back on the
  typed stem. Then queued behind `rotateTask` and `openTask` (the scan's list would bring the old name
  back), `Task.detached` `FileRenamer.rename` with sidecars per setting.
- On success: `cache.remove(old)`, `fullSizeCache.remove(old)`; `ready[new] = ready[old]`, `knownInfo` and
  `fileInfo` moved with `moved(to:)`; `sortValues[old]` dropped, `await readSortValues(for: [new])`; the
  list's URLs with old replaced by new → `relist`; `fileRevision += 1` (Info panel rereads). The image is
  not decoded again. `.taken` → its message, return false; other errors → "Couldn't rename \(name)".
- F2 (`NSF2FunctionKey`) next to F7 / F8 in `handle`; File menu "Rename…  (F2)" after Save As…; context
  menu "Rename…"; all disabled without `canChangeFile`. With the toolbar hidden or in full screen,
  `beginRename` shows `RenameSheet` (title "Rename", the field, the message line, Cancel / Rename) instead.
- While `renaming`, the viewer's single keys don't act (the field has the keyboard; `handle` returns
  `.ignored` when `model.renaming`).

- [ ] **Step 1: Implement;** `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; new strings in all 30 languages (keep "  (F2)"); `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: rename the image in the window title (F2), never overwriting`

---

### Task 8: New from Clipboard (⌘N)

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Clipboard.swift` (unsaved state, asking, saving),
  `Sources/Featherview/Viewer/CloseGuard.swift` (window delegate proxy)
- Modify: `ViewerModel.swift` (stored properties; the guard line in `next`, `previous`, `first`, `last`,
  `open`, `setZoom`; `hasPicture`; `zoomPercent`, `zoom(by:)`, `copyImage`, `saveAs`, `titleName`,
  `titleCounter` branches; a weak registry `static let all = NSHashTable<ViewerModel>.weakObjects()`),
  `ViewerView.swift` (File menu item, zoom items and toolbar zoom buttons on `hasPicture`, edited dot,
  `CloseGuard` installed in `WindowAccessor`), `ViewerToolbar.swift` (zoom buttons' `enabled`),
  `StatusBar.swift` (unsaved fields), `ConvenienceMenus.swift` (`ClipboardCommand`, `ClipboardWatch`),
  `Sources/Featherview/FeatherviewApp.swift` (quit asks), `SavePanel.swift` (`run(name:folder:window:)`),
  `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 3 holds the decode and save); Task 10 on screen.

**Interfaces:**
- Consumes: `ClipboardImage.image(from:)`, `preferredType`, `ImageSaver.save(_ image:…)`,
  `StatusLine.unsaved` (Task 3).
- Produces (Task 9 uses `unsaved`):
  - `ViewerModel.unsaved: CGImage?`, `coveredList: ImageList?`.
  - `func newFromClipboard()` — a pasteboard file URL that `ImageFormats.isDecodable` → `open(url)`;
    else `preferredType` data → `ClipboardImage.image(from:)` off the main thread → after asking about a
    current unsaved image, queued behind `rotateTask` / `openTask`: `coveredList = list` (kept if one is
    already covered), `list = ImageList(urls: [])`, `unsaved = image`, `image = image`, `fileInfo = nil`,
    `zoom = .fit`, `errorMessage = nil`. Undecodable → "Can't open the image on the clipboard".
  - `func leaveUnsaved(then action: @escaping @MainActor () -> Void)` — nil `unsaved` → `action()` at once
    (no cost on the browsing path); else the sheet of Decision 7; Don't Save or a successful Save… →
    `unsaved = nil`, `list = coveredList ?? list`, `coveredList = nil`, then `action()`; Cancel → nothing.
  - `func confirmDiscard() async -> Bool` — the same sheet for close and quit (true: go on).
  - `func saveUnsaved(thenOpen: Bool) async -> Bool` — `SavePanel.run(name: "Untitled", folder:
    coveredList's folder ?? Pictures, window:)`, `ImageSaver.save(image, …)` detached; `thenOpen`
    (S / ⇧⌘S) → `unsaved = nil`, `open(target)`; from the sheet → no open.
  - `Availability.hasPicture` = `hasCurrent || unsaved != nil` (zoom items and buttons only).
  - `CloseGuard: NSObject, NSWindowDelegate` — wraps the window's delegate like `MenuKeys`'s
    `DelegateProxy` (forwarding everything), answers `windowShouldClose` false while `unsaved != nil` and
    closes after `confirmDiscard()` is true.
  - `@MainActor @Observable final class ClipboardWatch { static let shared; private(set) var hasImage }` —
    re-checked on `didBecomeActiveNotification` and after `copyImage` writes; never at launch before the
    first image.

Rules:
- Guard lines: `next` and `previous` start with
  `if unsaved != nil { return leaveUnsaved { [weak self] in self?.show() } }` (the covered current image
  shows again, not a step further, Decision 7); `first`, `last` and `open` with the same line calling
  themselves again (`self?.first()`, …, `self?.open(url, remember: remember)`). `setZoom` skips
  `show(page:)` while `unsaved != nil` (the full-size picture needs no decode).
- `titleName` "Untitled" (`String(localized:)`), `titleCounter` nil, `window.isDocumentEdited = unsaved !=
  nil` (set from the view on change). `zoomPercent` at fit uses the unsaved image's size; `zoom(by:)` from
  fit too. `copyImage` copies the unsaved image (`ClipboardImage.pngData`). `saveAs` with `unsaved` →
  `saveUnsaved(thenOpen: true)`.
- `ClipboardCommand`: "New from Clipboard" ⌘N first in `CommandGroup(replacing: .newItem)`, disabled while
  `!ClipboardWatch.shared.hasImage`; acts on the focused viewer, else `ViewerModel.lastActive.current`.
- Quit: `applicationShouldTerminate` (before the batch check's `.terminateNow`) walks `ViewerModel.all`
  with `unsaved`, asks each in turn (`confirmDiscard`), `.terminateLater` and replies; Cancel → no quit.
- Follow New Files and the scan: nothing touches `list` while it is covered except `leaveUnsaved`
  (Task 9 respects it).

- [ ] **Step 1: Implement;** `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `swift run -c release featherview-bench browse /tmp/fv/browse --interval-ms 30` →
  unchanged against `main` (the guard lines are one nil check).
- [ ] **Step 3:** `scripts/strings.sh`; new strings ("New from Clipboard", "Untitled", the sheet's
  sentences and buttons "Save…", "Don't Save", "Cancel", the error) in all 30 languages; `swift test` → all PASS.
- [ ] **Step 4: Commit** `feat: New from Clipboard (⌘N), asking before an unsaved image is discarded`

---

### Task 9: View › Follow New Files

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Follow.swift`
- Modify: `ViewerModel.swift` (stored properties; `open(_:)` moves the watch), `ConvenienceMenus.swift`
  (the toggle), `ViewerView.swift` (View menu line; `onDisappear` stops the watch), `Resources/Localizable.xcstrings`
- Test: none new in Core (Task 4 holds the watch and arrival rules); Task 10 on screen.

**Interfaces:**
- Consumes: `FolderWatch`, `Arrivals` (Task 4); `relist`, `readSortValues(for:)` (Task 5); `unsaved`,
  `coveredList` (Task 8); `ImageList.select` (Task 1 / M13); `FolderScanner.images(around:sorted:)`.
- Produces:
  - `ViewerModel.followsNewFiles: Bool` — `didSet` starts or stops `folderWatch` on `folder`.
  - `func folderChanged()` — queued behind `rotateTask` and `openTask`; while `unsaved != nil` only marks
    `pendingRescan` (run by `leaveUnsaved`); otherwise rescans off the main thread (hidden files per
    setting), `Arrivals.diff` against `list.urls`, drops removed URLs from `ready`, `knownInfo`, both
    caches and `sortValues`, `await readSortValues(for: added)`, `relist(scanned)`. Then `Arrivals.newest`
    (modification dates read with the scan), `await Arrivals.settled(newest)` (cancelled by the next
    change or `open`), and if still listed and no rename field, folder chooser, F7 / F8 panel or unsaved
    image is up: `list.select(newest)`, `show()`.
  - `folderGone()` → `followsNewFiles = false`.

Rules:
- The View menu toggle "Follow New Files" sits under Sort By; bound to the focused model, disabled
  without `folder`. Off at launch for every window; not stored.
- A window closing (`onDisappear`) cancels its watch; `open(_:)` of another folder re-creates it there
  when following.

- [ ] **Step 1: Implement;** `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; "Follow New Files" in all 30 languages; `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: View › Follow New Files shows images as they arrive`

---

### Task 10: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folders: the corpus (`/tmp/fv/browse`), a 10,000-file
folder (copies of one corpus JPEG), a folder of photos with EXIF dates out of name order, a folder with
`IMG_1.jpg` + `IMG_1.xmp` + `IMG_1.AAE`, a QOI and a PDF.

- [ ] **Step 1: Check by hand** (release build), light and dark, then in Arabic (right-to-left):
  - Open Recent: files and a folder opened by ⌘O, drop and Finder appear newest first; browsed images
    don't; a renamed file's entry follows it; a trashed one is gone after reactivating; Clear Menu; the
    Dock menu lists the same (if it doesn't, add `applicationDockMenu(_:)` returning the same items and
    note it in the commit).
  - Rename: F2, File › Rename…, context menu, click on the title name; dragging the window by its title
    still moves it; the stem is selected; Return, clicking away, Esc; a clash (also with a sidecar's
    name), "/", leading ".", an extension change (Keep / Use); `img.jpg` → `IMG.jpg`; sidecars renamed;
    the image stays, the position updates in name order; with the toolbar hidden and in full screen the
    sheet shows.
  - Sort By: each key both ways on the EXIF folder; the current image stays; two windows re-sort together;
    a relaunch keeps the order; Date Taken on the 10,000 folder: first image at once, the list re-sorts later.
  - Share: toolbar, File menu (a submenu of services; if SwiftUI renders `ShareLink` there as a plain
    item, switch to `Menu("Share")` over `NSSharingService.sharingServices(forItems:)`), context menu;
    Mail gets the file.
  - Set as Desktop Picture on two screens (if attached; the maintainer's go covers changing the
    desktop), a rotated JPEG upright; disabled for QOI and PDF.
  - Float on Top over another app's window; disabled in full screen; a second window not floating.
  - New from Clipboard: a screenshot copied (⌘⌃⇧4), a Finder-copied JPEG (opens the file), text only
    (disabled); every way out asks (←, →, Home, ⌘O, a drop, a Finder file into that window, Open Recent,
    ⌘N, close, ⌘Q); Save…, Don't Save, Cancel each; R, L, ⌘⌫, F7, F2, I do nothing meanwhile; Save As
    writes PNG and HEIC; ⌘C copies it.
  - Follow New Files: copy a big file into the folder (shown once complete), export 50 files at once
    (newest shown once), delete the current file elsewhere (held), rename the folder (following turns off),
    while a rename field or the F7 panel is open (not interrupted).
- [ ] **Step 2: Measure** (`sudo -n /usr/bin/log show`, Points of Interest): cold launch with a file
  (< 410 ms, unchanged), a 10,000-file folder to first image in each sort order (< 500 ms), prefetched
  and not-prefetched `Navigate` (unchanged), memory with an unsaved 6K screenshot shown (the image plus
  the 8-image cache). Fix any miss before going on.
- [ ] **Step 3: Docs:** `docs/spec.md` gets a "Viewer conveniences" section under "Viewer" with Decisions
  1–8 in spec wording, F2 in "Keys", ⌘N and the new menu items in "Menu commands", Share in "Toolbar"
  and the context menu list in "Mouse and trackpad"; `docs/DESIGN.md` "Toolbar" gains the Share button
  and the rename field; `docs/parity.md` "Viewer conveniences" rows → Featherview column as built, status
  `v2`; roadmap row `| 11 | Viewer conveniences (v2) | docs/superpowers/plans/2026-10-22-milestone-11-viewer-conveniences.md | done |`;
  README features line.
- [ ] **Step 4: Commit** `docs: viewer conveniences done after manual QA`
