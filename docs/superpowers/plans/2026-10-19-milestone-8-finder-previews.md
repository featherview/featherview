# Featherview v1 — Milestone 8 Implementation Plan (Finder previews)

> **Milestone 8** in `docs/roadmap.md`. Builds on milestones 3 and 7, whose `OwnDecoders` registry and
> `ImageDecoder` it reuses unchanged. Don't add anything from other milestones here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Finder icons, Quick Look (Space) and open panels show the formats only Featherview reads
(QOI, PCX, DCX, XBM, XPM, WBMP, Sun Raster, IFF/ILBM, XCF, PaintShop Pro, Paint.NET), through two
app extensions that reuse FeatherviewCore's decoders.

**Architecture:** Two sandboxed app extensions inside `Featherview.app/Contents/PlugIns/`: a thumbnail
extension (`QLThumbnailProvider`) and a data-based preview extension (`QLPreviewProvider`, macOS 12+).
Each is a SwiftPM executable target linked against `FeatherviewCore` whose entry point is
`_NSExtensionMain`; `scripts/bundle.sh` wraps each binary in an `.appex` with its own Info.plist and
signs it ad hoc with the sandbox entitlement before signing the app. What can be tested without
Quick Look (which types, what size, which decode) lives in `FeatherviewCore` as `QuickLookSupport`;
the extensions are a few lines each. The app itself doesn't change, so launch time can't move.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, QuickLookThumbnailing, QuickLookUI
(`QLPreviewProvider`, `QLPreviewReply`), ImageIO via `ImageDecoder`, Swift Testing.

**Spec:** `docs/spec.md` "Formats" (the "Finder previews" line); `docs/roadmap.md` section 8. Rules,
budgets and commands: `AGENTS.md`. Read all three first.

**Checked while planning (spikes on macOS 27, not committed):**

- A SwiftPM `executableTarget` linking `FeatherviewCore` with
  `linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]` and a
  `main.swift` holding only a comment builds with `swift build -c release --product <Target>` (no
  `products:` entry needed) into a 2.5 MB binary whose entry point is `_NSExtensionMain`.
- Wrapped as `<App>.app/Contents/PlugIns/<Name>.appex` (Info.plist below, `CFBundlePackageType` `XPC!`),
  signed `codesign --force --sign - --entitlements <file>` with `com.apple.security.app-sandbox` and
  `com.apple.security.files.user-selected.read-only`, then the app signed ad hoc without `--deep`:
  macOS registered it once the app sat in `~/Applications` and was registered (`lsregister -f -R`,
  `pluginkit -a`), and launched it sandboxed for a QOI and an XCF. `FeatherviewCore` decoded the file
  inside the sandbox from `request.fileURL` with no extra entitlement.
- `qlmanage -t` does **not** use thumbnail extensions (it falls back to ImageIO and fails). Finder's
  API, `QLThumbnailGenerator.shared.generateBestRepresentation`, does: representation type
  `.thumbnail` (raw value 2), first call 75–180 ms (extension launch), then about 8–20 ms.
- In `QLThumbnailReply(contextSize:currentContextDrawing:)` and the `(contextSize:drawing:)` variant
  the context is in **pixels**: drawing into `CGRect(origin: .zero, size: contextSize)` filled only the
  lower-left quarter at scale 2. Draw into `context.boundingBoxOfClipPath` (the whole context,
  whatever its units).
- The type identifiers: our own imported types from `Resources/Info.plist`
  (`net.mynetx.featherview.qoi`, `.pcx`, `.dcx`, `.xpm`, `.wbmp`, `.sun-raster`, `.ilbm`, `.xcf`,
  `.pdn`, `.psp`) plus the system's `public.xbitmap-image` for XBM. PDF and SVG are macOS's own
  (spec: "Formats ImageIO reads are left to macOS"), so they're left out.
- The preview extension couldn't be checked without the screen (Quick Look's panel is the only
  caller); Task 4 checks it.

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency.
- No new dependency. Apple frameworks only: QuickLookThumbnailing, QuickLookUI, ImageIO.
- `FeatherviewCore` never imports SwiftUI, AppKit or the Quick Look frameworks.
- Spec: "a Quick Look preview and thumbnail extension for the formats only Featherview reads, reusing
  its decoders, so Finder, Quick Look (Space) and open panels show them too. Formats ImageIO reads are
  left to macOS."
- Bundle ID stays `net.mynetx.featherview`; the extensions are `net.mynetx.featherview.thumbnail` and
  `net.mynetx.featherview.preview` (an extension's ID must start with its app's).
- Ad-hoc signing only (spec "Distribution"); no Developer ID, no notarization, no Xcode project
  (`AGENTS.md`: Swift Package Manager + `scripts/bundle.sh`).
- Performance budgets in `AGENTS.md` unchanged: the app binary and its launch path don't change.
- A file that can't be decoded gets no thumbnail (Finder shows its generic icon) and no preview; the
  extension never crashes or hangs on it.
- Commit messages: conventional commits, no AI attribution lines, no dates in docs or comments.
- Keep `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A damaged or crafted file in a folder Finder shows (truncated QOI, an XCF claiming 60,000 × 60,000):
  no thumbnail, the generic icon, no crash loop. The decoders already throw; pinned in Task 1
  (`corruptFileThrows`) and checked in Task 4 with a truncated file in the folder.
- Upper-case extensions (`IMAGE.QOI`, `SCAN.PCX`): Finder resolves the type case-insensitively, so the
  extension gets them; `OwnDecoders.format(for:)` lowercases. Pinned in Task 1
  (`upperCaseExtensionDecodes`).
- A multi-page DCX: the thumbnail and the preview show page 1, at page 1's size. Pinned in Task 1
  (`multiPageShowsFirstPage`).
- A transparent image (XCF, QOI with alpha): the thumbnail keeps its transparency, no black or white
  box behind it. Pinned in Task 2 (headless check of a corner pixel's alpha) and seen in Task 4.
- A small image (a 16 × 16 XBM icon) isn't blown up to 256 points; a large one fits inside the
  requested box keeping its aspect ratio. Pinned in Task 1 (`thumbnailSizeFits`, `smallImageIsNotEnlarged`).

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | the Core pieces both extensions use |
| B | 2 | thumbnail extension and the bundle.sh plumbing (the only one checkable headless) |
| C | 3 | preview extension (same plumbing, so after 2) |
| D | 4 | screen check, docs (main session; ask the maintainer before using the screen) |

---

### Task 1: QuickLookSupport in FeatherviewCore

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/QuickLookSupport.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/QuickLookSupportTests.swift`

**Interfaces:**
- Consumes: `ImageDecoder.decode(_:maxPixelSize:fitting:page:)`, `PixelSize`, `OwnDecoders.all`,
  `QOICodec.encode(_:)`, `PCXCodec.encode(_:)`, `RGBAImage`, `Fixtures.makeTempDir()`.
- Produces:
  - `public enum QuickLookSupport`
  - `public static let contentTypes: [String]` — exactly, in this order:
    `net.mynetx.featherview.qoi`, `net.mynetx.featherview.pcx`, `net.mynetx.featherview.dcx`,
    `public.xbitmap-image`, `net.mynetx.featherview.xpm`, `net.mynetx.featherview.wbmp`,
    `net.mynetx.featherview.sun-raster`, `net.mynetx.featherview.ilbm`, `net.mynetx.featherview.xcf`,
    `net.mynetx.featherview.psp`, `net.mynetx.featherview.pdn`.
  - `public static func thumbnailSize(image: CGSize, maximum: CGSize) -> CGSize` — the image scaled
    by `min(1, maximum.width / image.width, maximum.height / image.height)`; never larger than the
    image, aspect ratio kept.
  - `public static func thumbnail(_ url: URL, maximum: CGSize, scale: CGFloat) throws -> (image: CGImage, size: CGSize)`
    — decodes page 0 with `maxPixelSize` = `Int((max(maximum.width, maximum.height) * scale).rounded(.up))`;
    `size` is `thumbnailSize(image: <decoded pixel size>, maximum: maximum)`.
  - `public static func preview(_ url: URL, screens: [PixelSize]) throws -> CGImage` — page 0
    decoded to fit the screens, as the viewer does (`ImageDecoder.decode(url, fitting: screens)`).

- [x] **Step 1: Write the failing tests** in `QuickLookSupportTests`:
  - `contentTypesAreTheOwnFormats`: read `Resources/Info.plist` from the repo (`Fixtures.repo`), map each `UTImportedTypeDeclarations` entry's
    `public.filename-extension` values to its `UTTypeIdentifier`, add `xbm` → `public.xbitmap-image`.
    For every format in `OwnDecoders.builtIn` except `PDF` (SVG is the app's, registered at launch; `all` also holds formats other tests register), every extension maps
    to an identifier in `contentTypes`; and every identifier in `contentTypes` is reached by some own
    format. (Catches a new own format added without a Finder preview, and a stale type.)
  - `thumbnailSizeFits`: 400 × 267 in 256 × 256 → 256 × 170.88 (±0.01); 267 × 400 → 170.88 × 256.
  - `smallImageIsNotEnlarged`: 16 × 16 in 256 × 256 → 16 × 16.
  - `thumbnailDecodesAQOI`: a 400 × 300 QOI written with `QOICodec.encode` into a temp dir;
    `thumbnail(url, maximum: 256 × 256, scale: 2)` → image at least 512 px wide or the full 400,
    `size` 256 × 192.
  - `upperCaseExtensionDecodes`: the same bytes saved as `IMAGE.QOI` decode.
  - `multiPageShowsFirstPage`: a two-page DCX built in the test (the DCX header: magic `0x3ADE68B1`
    little-endian, then little-endian UInt32 page offsets, a zero, then the PCX pages from
    `PCXCodec.encode`; pages 40 × 30 and 10 × 10) → `size` is page 1's, 40 × 30 (never enlarged).
  - `corruptFileThrows`: the QOI's first 20 bytes saved as `cut.qoi` → `thumbnail` and `preview` throw.
  - `previewFitsTheScreen`: a 4000 × 3000 QOI with `screens: [PixelSize(width: 1000, height: 1000)]`
    → longest side ≤ 2000 (the viewer's at-most-2×-per-side rule), and ≥ 1000.
- [x] **Step 2: Run them to see them fail.** `swift test --filter QuickLookSupportTests` → fails to
  compile (`QuickLookSupport` not defined).
- [x] **Step 3: Implement** `QuickLookSupport` to the interfaces above in
  `Sources/FeatherviewCore/Imaging/QuickLookSupport.swift` (CoreGraphics, Foundation only).
- [x] **Step 4: Run the tests, then the full suite.** `swift test` → all pass.
- [x] **Step 5: Commit.** `feat: Quick Look types, thumbnail size and preview decode in the core`

---

### Task 2: Thumbnail extension and the bundle plumbing

**Files:**
- Modify: `Package.swift` (one target)
- Create: `Sources/FeatherviewThumbnail/ThumbnailProvider.swift`, `Sources/FeatherviewThumbnail/main.swift`
- Create: `Resources/QuickLook/Thumbnail-Info.plist`, `Resources/QuickLook/QuickLook.entitlements`
- Modify: `scripts/bundle.sh`
- Modify: `Sources/FeatherviewBench/main.swift` (a `thumbnail` command)
- Test: `Tests/FeatherviewCoreTests/Imaging/QuickLookSupportTests.swift` (one more test)
- Modify: `AGENTS.md` (Layout block and Commands)

**Interfaces:**
- Consumes: `QuickLookSupport.thumbnail(_:maximum:scale:)`, `QuickLookSupport.contentTypes` (Task 1).
- Produces: `build/Featherview.app/Contents/PlugIns/FeatherviewThumbnail.appex`; in `bundle.sh` a
  shell function `appex <Target> <Info.plist>` that Task 3 calls once more; the bench command
  `featherview-bench thumbnail <file>... [--out <dir>]`.

Facts to pin:

- `Package.swift`: `.executableTarget(name: "FeatherviewThumbnail", dependencies: ["FeatherviewCore"],
  linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])])`, with a
  one-line comment that SwiftPM can't make app extensions, so `bundle.sh` wraps this binary.
  `main.swift` holds only a comment saying the entry point is `_NSExtensionMain`.
- `ThumbnailProvider: QLThumbnailProvider` (`final class`, the principal class
  `FeatherviewThumbnail.ThumbnailProvider`): `provideThumbnail(for:_:)` calls
  `QuickLookSupport.thumbnail(request.fileURL, maximum: request.maximumSize, scale: request.scale)`
  and replies `QLThumbnailReply(contextSize: size) { context in context.draw(image, in: context.boundingBoxOfClipPath); return true }`;
  on a thrown error it calls `handler(nil, error)`.
- `Thumbnail-Info.plist`: `CFBundleExecutable` `FeatherviewThumbnail`, `CFBundleIdentifier`
  `net.mynetx.featherview.thumbnail`, `CFBundleName` `FeatherviewThumbnail`, `CFBundlePackageType`
  `XPC!`, `CFBundleInfoDictionaryVersion` `6.0`, `LSMinimumSystemVersion` `14.0`, and
  `NSExtension` = { `NSExtensionPointIdentifier` `com.apple.quicklook.thumbnail`,
  `NSExtensionPrincipalClass` `FeatherviewThumbnail.ThumbnailProvider`, `NSExtensionAttributes` =
  { `QLSupportedContentTypes` = the eleven identifiers, `QLThumbnailMinimumDimension` 0 } }.
  No version keys in the file: `bundle.sh` copies `CFBundleShortVersionString` and `CFBundleVersion`
  from the app's Info.plist, so they can't drift.
- `QuickLook.entitlements`: `com.apple.security.app-sandbox` true and
  `com.apple.security.files.user-selected.read-only` true (what the spike ran with).
- `bundle.sh`: build `FeatherviewThumbnail` with the same `-c "$CONFIG" $LINK` as the app; function
  `appex` creates `$APP/Contents/PlugIns/<Target>.appex/Contents/MacOS/`, copies the binary and the
  plist (as `Contents/Info.plist`), sets the two version keys with
  `plutil -replace … -string "$(plutil -extract … raw Resources/Info.plist)"`, and signs it with
  `codesign --force --sign - --entitlements Resources/QuickLook/QuickLook.entitlements`. Extensions are
  signed before the app's existing `codesign --force --sign - "$APP"` (no `--deep`).
- The bench's `thumbnail` command calls `QLThumbnailGenerator.shared.generateBestRepresentation` with
  `size` 256 × 256, `scale` 2, `representationTypes: .thumbnail`, and prints one line per file:
  `<name>: thumbnail <w>x<h> <ms> ms` when the representation's type is `.thumbnail`, otherwise
  `<name>: no thumbnail (<type or error>)`; with `--out` it also writes `<name>.png`. Exit 1 if any
  file got no thumbnail. Add it to `usage`.

- [x] **Step 1: Write the failing test** `extensionPlistsListTheContentTypes` in
  `QuickLookSupportTests`: for each of `Resources/QuickLook/Thumbnail-Info.plist` and
  `Resources/QuickLook/Preview-Info.plist` that exists on disk, its
  `NSExtension.NSExtensionAttributes.QLSupportedContentTypes` equals `QuickLookSupport.contentTypes`;
  at least one of them must exist.
- [x] **Step 2: Run it to see it fail.** `swift test --filter extensionPlistsListTheContentTypes` → fails (no plist).
- [x] **Step 3: Add** the target, `ThumbnailProvider`, the plist, the entitlements and the `bundle.sh`
  changes to the facts above.
- [x] **Step 4: Run the tests.** `swift test` → all pass.
- [x] **Step 5: Build and inspect the bundle.** `scripts/bundle.sh release`, then
  `codesign -dv --entitlements - build/Featherview.app/Contents/PlugIns/FeatherviewThumbnail.appex`
  shows `Identifier=net.mynetx.featherview.thumbnail` and the sandbox key;
  `codesign --verify --strict build/Featherview.app` passes;
  `plutil -extract CFBundleShortVersionString raw build/Featherview.app/Contents/PlugIns/FeatherviewThumbnail.appex/Contents/Info.plist`
  prints the app's version.
- [x] **Step 6: Add the bench `thumbnail` command** to the facts above.
- [x] **Step 7: Check it headless.** Copy the app to a scratch `~/Applications/Featherview Check.app`
  (macOS found the spike's extension there, not in a temp folder), then
  `lsregister -f -R` it and `pluginkit -a` its appex
  (`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`);
  `pluginkit -m -v -i net.mynetx.featherview.thumbnail` lists it. Write a 400 × 300 QOI with half its
  pixels transparent (a short `swift` script using `QOICodec`, or `magick … qoi:` if installed) and run
  `swift run -c release featherview-bench thumbnail <that file> <a sample XCF from
  /Users/jm/Web/mx/featherview/research/appformats/xcf/> --out <scratch dir>` → two
  `thumbnail` lines; the QOI's PNG has alpha 0 in its transparent corner
  (`magick <png> -format "%[fx:p{0,0}.a]" info:` → `0`). Then remove the copy:
  `pluginkit -r`, `lsregister -u`, delete it, `qlmanage -r cache`.
- [x] **Step 8: AGENTS.md.** Layout block: `Sources/FeatherviewThumbnail/`, `Sources/FeatherviewPreview/`
  (Finder thumbnail and Quick Look preview extensions, wrapped into `.appex` by `scripts/bundle.sh`)
  and `Resources/QuickLook/`. Commands: the bench `thumbnail` line, and that `pluginkit -m -v -p
  com.apple.quicklook.thumbnail` shows which copy of the app macOS uses.
- [x] **Step 9: Commit.** `feat: Finder thumbnails for the formats only Featherview reads`

---

### Task 3: Preview extension

**Files:**
- Modify: `Package.swift` (one target, same shape as Task 2's)
- Create: `Sources/FeatherviewPreview/PreviewProvider.swift`, `Sources/FeatherviewPreview/main.swift`
- Create: `Resources/QuickLook/Preview-Info.plist`
- Modify: `scripts/bundle.sh` (one more `appex` call)

**Interfaces:**
- Consumes: `QuickLookSupport.preview(_:screens:)`, `PixelSize` (Task 1); `appex` in `bundle.sh` and
  `QuickLook.entitlements` (Task 2).
- Produces: `build/Featherview.app/Contents/PlugIns/FeatherviewPreview.appex`.

Facts to pin:

- `PreviewProvider: QLPreviewProvider, QLPreviewingController` (`final class`, principal class
  `FeatherviewPreview.PreviewProvider`) with
  `func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply`.
  Screens: `NSScreen.screens` mapped to `PixelSize` of `frame.size × backingScaleFactor`, rounded.
  Reply: `QLPreviewReply(contextSize: <image size in points>, isBitmap: true) { context, _ in context.draw(image, in: context.boundingBoxOfClipPath) }`,
  points = pixels ÷ the largest `backingScaleFactor` among the screens (1 when there is none).
  Errors propagate (`throws`): Quick Look then shows its generic file view.
- `Preview-Info.plist`: as `Thumbnail-Info.plist` with `FeatherviewPreview` names, identifier
  `net.mynetx.featherview.preview`, `NSExtensionPointIdentifier` `com.apple.quicklook.preview`, and
  attributes `QLIsDataBasedPreview` true, `QLSupportsSearchableItems` false,
  `QLSupportedContentTypes` = the eleven identifiers.

- [x] **Step 1: Run** `swift test --filter extensionPlistsListTheContentTypes` after adding only the
  plist with a deliberately wrong list (drop `public.xbitmap-image`) → fails; restore the list → passes.
- [x] **Step 2: Add** the target, `PreviewProvider` and the `bundle.sh` call to the facts above.
- [x] **Step 3: Build and inspect.** `swift test` → all pass. `scripts/bundle.sh release`;
  `codesign -dv --entitlements - build/Featherview.app/Contents/PlugIns/FeatherviewPreview.appex`
  shows the identifier and the sandbox key; `codesign --verify --strict build/Featherview.app` passes.
  Registration check as in Task 2 Step 7: `pluginkit -m -v -i net.mynetx.featherview.preview` lists
  it (the preview itself needs the screen: Task 4).
- [x] **Step 4: Commit.** `feat: Quick Look previews for the formats only Featherview reads`

---

### Task 4: Check on screen, docs (main session; needs the screen, ask the maintainer first)

Workflow agents can't use the screen. Build `scripts/bundle.sh release`, copy it to
`~/Applications/Featherview.app` (replacing an older copy there only after asking the maintainer),
open a scratch folder of samples: one file of each of the eleven types (generated with our own
encoders or taken from `research/appformats/` and the earlier real-world samples), a transparent
XCF, a two-page DCX, `BIG.QOI` in capitals, a truncated QOI, a 16 × 16 XBM.

- [x] **Finder:** icon view shows a thumbnail for every type, transparency kept, the small XBM small,
  the truncated file with a generic icon; Column view's preview column too.
  Checked on `main` (3689ff3) with 25 samples, the 11 formats added after M8 included: every file
  has a thumbnail, the truncated QOI a generic icon. Finder draws the 32-pixel thumbnail of the
  16 × 16 XBM enlarged in a white frame at icon size 128; the extension never enlarges.
- [x] **Quick Look:** Space on each shows the image sharp on a Retina screen (if it's soft or a quarter
  of the window, fix the context-size arithmetic in `PreviewProvider`); the DCX shows page 1; the
  truncated file shows Quick Look's generic view; arrow keys move between files in the panel.
- [x] **Open panel:** Featherview's ⌘O panel and another app's open panel (TextEdit) show the thumbnail
  and the preview in the panel's preview pane.
  Checked: both panels show the thumbnails in icon view and the full preview in column view.
  Checked: the DCX showed page 1 at half the size a PNG of it gets (pixels divided by the Retina
  scale); fixed to one point per pixel, fitted to the screen, like Quick Look's own PNG preview.
  The truncated file shows the generic view, ↓ steps through the files in the panel, text in
  BIG.QOI is sharp enough for Live Text.
- [x] **Download path:** build the English disk image (`scripts/dmg.sh en`), mark it as downloaded
  (`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <dmg>`), install the app
  from it, open it once (Open Anyway as the README says), then check one thumbnail and one preview
  again. If macOS won't run the extensions of an ad-hoc signed downloaded app, write that into
  `docs/spec.md` "Distribution" and the README instead of working around it.
  Checked on 2026-10-19 with the English disk image, quarantined: Gatekeeper blocks the first open,
  Open Anyway asks for an administrator's password, and after that one open the extensions register
  (both switches on in System Settings › Login Items & Extensions › Quick Look) and Space previews
  work. Thumbnails then failed for a reason unrelated to the download (a Quick Look agent running
  since days with stale type data, see the Finder step); they work from a fresh agent.
- [x] **Budgets:** launch with a 12 MP JPEG after a real ⌘Q (6 runs, median of 2–6) is unchanged
  against the number in `AGENTS.md`; note the app bundle's size before and after (`du -sh`).
- [x] **A big file:** the largest sample XCF and PSP: thumbnail time from the bench `thumbnail`
  command, and Finder stays responsive while it draws. Watch the extension's memory too (Activity
  Monitor, `FeatherviewThumbnail`) with a folder of several large PSP/XCF files: the own decoders
  decode at full size before scaling, and Finder asks for several thumbnails at once.
  Checked: bench thumbnail 1.1 s for a 56 MB XCF, PSPs at most 89 ms. Finder icon view on 81 files
  (the 5 largest real XCFs and the PSP samples, 3 copies each, 500 MB, cold cache): Finder answered
  every request within 476 ms while the thumbnails drew; the extension processes peaked at 954 MB
  together and fell back to 33 MB.
  Checked on `main` (076da8b, /Applications, M1 Pro, load average 3–4): a 4032 × 3024 JPEG alone in
  a folder, 6 launches after an AppleScript quit, `first image … ms after launch`: 389 (warm-up), 370,
  407, 382, 374, 381; median of runs 2–6 381 ms, unchanged against the ~380 ms in `AGENTS.md`. App
  bundle 13 MB (the two extensions 2.4 MB each, JPEG XR's jxrlib about 0.4 MB) against 7.2 MB before.
- [x] **Docs:** README feature list (Finder thumbnails and Quick Look for the formats macOS can't
  read), `docs/roadmap.md` row 8 → `done`, tick this plan. Remove the `~/Applications` copy only if
  it wasn't there before. Commit `docs: milestone 8 done after manual QA`.
  Done: README features and install note, roadmap row 8 done, this plan ticked.
