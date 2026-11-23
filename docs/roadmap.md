# Featherview v1 roadmap

`docs/spec.md` says what v1 is. This file splits it into five milestones, each shippable and
testable on its own. Each milestone gets its own detailed plan in `docs/superpowers/plans/`,
written (superpowers:writing-plans) when the previous milestone is merged, so it can use the real
interfaces instead of guessed ones. Run a milestone's plan wave by wave with the `plan-wave`
workflow.

Plans of done milestones are in git history only: `git show 5dcca24:<plan path>` (milestones 1–21),
`git show ba4b62f:<plan path>` (22–25).

Milestones marked **observe first** have reference-viewer behaviour not yet recorded in
`docs/parity.md`; run the `observe-reference` skill for those items before writing the plan.

| # | Milestone | Plan | Status |
|---|---|---|---|
| 1 | Core viewer and batch | `docs/superpowers/plans/2026-10-15-featherview-v1.md` | done |
| 2 | Viewer complete | `docs/superpowers/plans/2026-10-16-milestone-2-viewer-complete.md` | done |
| 3 | Formats and Save As | `docs/superpowers/plans/2026-10-16-milestone-3-formats-save-as.md` | done |
| 4 | Batch complete | `docs/superpowers/plans/2026-10-17-milestone-4-batch-complete.md` | done |
| 5 | WebP output | `docs/superpowers/plans/2026-10-16-milestone-5-webp.md` | done |
| 6 | Languages | `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` | done |
| 7 | App formats | `docs/superpowers/plans/2026-10-17-milestone-7-app-formats.md` | done |
| 8 | Finder previews | `docs/superpowers/plans/2026-10-19-milestone-8-finder-previews.md` | done |
| 9 | Animation (v2) | `docs/superpowers/plans/2026-10-22-milestone-9-animation.md` | done |
| 10 | Document icon (v2) | `docs/superpowers/plans/2026-10-22-document-icon.md` | done |
| 11 | Viewer conveniences (v2) | `docs/superpowers/plans/2026-10-22-milestone-11-viewer-conveniences.md` | done |
| 12 | Zoom modes and flip (v2) | `docs/superpowers/plans/2026-10-22-milestone-12-zoom-modes-flip.md` | done |
| 13 | Thumbnail grid (v2) | `docs/superpowers/plans/2026-10-22-milestone-13-thumbnails.md` | done |
| 14 | Slideshow (v2) | `docs/superpowers/plans/2026-10-22-milestone-14-slideshow.md` | done |
| 15 | Compare images (v2) | `docs/superpowers/plans/2026-10-22-milestone-15-compare.md` | done |
| 16 | Batch extras (v2) | `docs/superpowers/plans/2026-10-22-milestone-16-batch-extras.md` | done |
| 17 | JPEG XL writing (v2) | `docs/superpowers/plans/2026-10-22-milestone-17-jpeg-xl-writing.md` | done |
| 18 | Quick wins (v2): Refresh, random image, desktop placement, grid tooltips | `docs/superpowers/plans/2026-10-22-milestone-18-quick-wins.md` | done |
| 19 | Simplify: decisions from the app into tested Core types, catalog format, duplicates | `docs/superpowers/plans/2026-10-22-milestone-19-simplify.md` | done |
| 20 | Hardening: fuzzing, sanitizers, real files through every write path, Intel, crash reports | `docs/superpowers/plans/2026-10-23-milestone-20-hardening.md` | done |
| 21 | Grid columns that fill the window, right-click menu, drag out | `docs/superpowers/plans/2026-10-25-milestone-21-grid-columns-menu-drag.md` | done |
| — | Automatic updates through Sparkle (spec "Updates") | no plan; commits 0949b8d, a5f9bd3 | done |
| — | First open on every account (spec "Distribution"): disk image background stored in its `.DS_Store`, "Read Me First" file with the Terminal line, Homebrew cask `postflight`, website card | no plan; branch `release-0.12.1` (3a5da45, a046241, 796c52b), merged into main | done, shipped in 0.12.1: tested on this Mac as a standard user with a quarantined image (Finder copy with admin prompt, line without admin, launch without prompt) and a quarantined Homebrew install into `~/Applications` |
| 22 | Photos library: browse albums, drops from Photos, batch from and into the library | `docs/superpowers/plans/2026-10-26-milestone-22-photos-library.md` | done: tasks 1–10. Screen check (release, this Mac's library of 3,686): one Photos prompt on first Open from Photos; sheet keys, counts, Library at the newest picture; arrows, Home, grid, info panel with place, 100 % zoom, ⌘C, Save As, F8; an iCloud-only picture shows a fitted preview, "Downloading from iCloud…", then sharpens; Delete shows Photos' prompt, Don't Allow keeps the picture. Opening the library to its first picture ~240 ms, next p50 ~14 ms, p95 ~135 ms (`featherview-bench photos`). Fixed in the check: sheet keys went to the viewer. Shipped in 0.13.0; in 0.13.1 an iCloud-only picture's preview is the largest one Photos keeps locally (768 × 1024 on this library, was 64 × 48), 3 ms more at p50 |
| 23 | Info panel: histogram, exposure card, foldable groups, place names, all metadata, keyboard focus and VoiceOver (runs before 22) | `docs/superpowers/plans/2026-10-28-milestone-23-info-panel.md` | done, shipped in 0.12.0: place names in the app's language; screen check: `Navigate` with the panel open over 200 12 MP JPEGs p50 19.9 ms, p95 21.9 ms; first place 75–79 ms after the panel opens, cold; keyboard, All Metadata keys, VoiceOver tree, German light, Arabic dark, Increase Contrast, Reduce Motion (groups fold as a cut) |
| 24 | Huge pictures: own readers for 8-bit RGB PSD/PSB and huge TIFF at the size needed, zoom by parts | `docs/superpowers/plans/2026-10-30-milestone-24-huge-pictures.md` | done: screen check on heic1502a.psb and both Hubble TIFFs: shipped in 0.13.0; first image 525 ms after launch (PSB; about 2 s from double-click on a first, uncached opening, app launch included), parts at 100 % 36–60 ms (PSB) and 119–148 ms (TIFF) while panning, app footprint at most 327 MB; 12 MP JPEG `Navigate` p50 21 ms, p95 24 ms |
| 25 | Photoshop layers: files without a stored composite drawn from their layers, every blend mode, groups, masks, fills, adjustment layers (runs before 22) | `docs/superpowers/plans/2026-10-30-milestone-25-photoshop-layers.md` | done: tasks 1–9. Oracle: 104 of 108 unique comparable files within target (96.3 %, target ≥ 95 %); over, with `shortcut:` comments: Brightness/Contrast's curve, Hue/Saturation on near greys, gradients mixed in Photoshop's working space, noise gradients' generator (none described in Adobe's spec). Fit decode of the 12 MP, 30-layer file ~292 ms (budget < 500 ms). Screen check (release): all 55 corpus files without a composite show a picture, none blank or failing; grid shows all; files with layer effects show without them; first image 399–400 ms after launch; slowest fit decode in the folder 16 ms. Finder and Quick Look: PSB through our extensions (macOS's own thumbnailer draws none; Quick Look keeps its earlier pick of extension until the next login), PSD stays macOS's (a failure isn't handed on to another extension, FB25383955) |
| — | 1.0: polish and hardening. No new features until 1.0: fixes from early users, a simplify pass per area over the milestones that never had one (Core/Formats, Core/Imaging, Core/Viewer+Batch+App, the app, bench and extensions), stability, memory and speed on more real-world files, translations reviewed by native speakers, notarization once sponsors cover the fee. After 1.0, features by request in Discussions | plan to write next (0.13.0 is out) | planned |

## Next version (after v2)

Ideas from the maintainer's QA that no spec covers yet; each gets a plan and a spec section first.

- Live Text (idea, after 1.0; [Discussions #7](https://github.com/featherview/featherview/discussions/7)):
  text in the shown picture can be selected and copied like in Preview, with links, phone numbers,
  addresses and dates active. macOS's own VisionKit analysis, on the device; it starts only once the
  user stays on a picture (never while flipping through or prefetching), runs off the main thread on
  the screen-size decode, and stays out of the browsing, launch and memory budgets.

- Accessibility pass for the whole app (idea): the info panel has full keyboard focus and VoiceOver
  (M23); the same for toolbar, grid, batch window, sheets and Settings (focus rings, VoiceOver labels,
  Increase Contrast) follows its pattern.
