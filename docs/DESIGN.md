# Featherview viewer — design spec

The look of the viewer chrome, in Markdown. Source: the design canvas
<https://claude.ai/artifact/MBFkpbRchvBUixdnsAXveQ> (private to the maintainer); a copy of its
artboards is in `docs/design/canvas/project/` (`canvas.json` lists them, `Spec.dc.html` is this
page). The artboards reference sample photos as `/_blob/…` uploads: those photos are not part of
the repo, so the pictures don't show when the files are opened locally.

Tokens live in `Sources/Featherview/Design/Theme.swift`; `docs/spec.md` stays the source of
behaviour. Artboards are 1220 × 700 pt windows at 1x (1 CSS px = 1 pt); every size, colour and
shadow in their inline CSS is authoritative.

Known correction: on the Chooser and Move artboards Forward is drawn disabled at the last image.
That is right only when "Past the end of a folder" is "Stop"; with "Show the folder chooser"
(or "Start this folder again") Forward stays enabled.

All values in points (pt), window shown at 1220 × 700 pt. Leading / trailing throughout; the
layout mirrors for RTL, the picture never does. macOS 26 Liquid Glass; macOS 14/15 system material
fallback.

## Principles

1. **The picture is the only solid thing.** Every control floats on glass and is translucent; the
   picture is opaque and the only element with a real shadow. Chrome never competes with it.
2. **One glass recipe, two shapes.** Capsule (toolbar groups, status strip), 16 pt card (panels,
   sheets). Same fill, highlight and hairline everywhere.
3. **Numbers are quiet and aligned.** Everything numeric is secondary colour with tabular figures
   (SF Pro monospaced digits) so the strip and panels never jitter while browsing.

## Colour tokens

Every window follows the app's appearance (Settings › Viewer › Appearance: System, Light, Dark);
toolbar, title bar and glass with it. Use system dynamic colours where one exists.

| Token | Dark (Graphite) | Light (Grey) | Use |
|---|---|---|---|
| Background | #1C1C20 (Graphite) | #E7E7EC (Grey) | Window and area behind the picture. |
| Glass fill | rgba(52,52,58,0.55) | rgba(255,255,255,0.60) | Toolbar groups, status strip, message boxes. Behind it: blur 40, saturation 180 %. |
| Glass fill · panel | rgba(44,44,50,0.62) | rgba(255,255,255,0.66) | Info panel (reads over the picture edge). |
| Glass fill · sheet | rgba(36,36,42,0.66) | rgba(255,255,255,0.72) | Folder chooser, Move to Folder. Slightly denser: text sits over a photo. |
| Glass highlight | rgba(255,255,255,0.12) inset 0 1 0 | rgba(255,255,255,0.70) inset 0 1 0 | 1 pt top edge light. On macOS 26 the glass provides this itself: skip it there. |
| Glass hairline | rgba(255,255,255,0.06) inset 0 0 0 1 | rgba(0,0,0,0.06) inset 0 0 0 1 | Shape outline. |
| Shadows | see Elevation | see Elevation | Never a one-off value; every floating thing takes a level from the scale. |
| Picture hairline | rgba(255,255,255,0.06) 1 pt | rgba(0,0,0,0.08) 1 pt | With the picture's E3 shadow, only while the picture fits inside the fit area. Both go the moment it overflows (zoomed). |
| Label · primary | rgba(255,255,255,0.85) | rgba(0,0,0,0.85) | Title, row labels, glyphs (.labelColor). |
| Label · secondary | rgba(255,255,255,0.55) | rgba(0,0,0,0.55) | Counter in the title, values, counts (.secondaryLabelColor). |
| Label · strip | rgba(255,255,255,0.70) | rgba(0,0,0,0.65) | Status strip text (between primary and secondary for 11 pt legibility). |
| Label · tertiary | rgba(255,255,255,0.40) | rgba(0,0,0,0.40) | "Empty", footer hints, "end of folder" (.tertiaryLabelColor). |
| Disabled glyph | rgba(255,255,255,0.30) | rgba(0,0,0,0.25) | Back/forward at either end, whole toolbar in the empty window. |
| Separator | rgba(255,255,255,0.14) | rgba(0,0,0,0.12) | 1 pt dividers inside capsules and strip; row separators 0.10 / 0.08. |
| Key cap | fill rgba(255,255,255,0.07), line 0.14, text 0.70 | fill rgba(0,0,0,0.05), line 0.12, text 0.60 | ⌘O, O, →, ←, ↩, esc, and the 1–0 / B–E keys in F7. |
| Accent | #FF7A59 (feather coral) | #B8552B (feather brown) | The app's accent colour (`Resources/Assets.xcassets`, `NSAccentColorName`): selected row fill and prominent buttons with on-accent text (white in light, graphite #1C1C20 in dark: white on the coral is 2.6:1), toggled-on toolbar glyph, switches, Settings tab. macOS uses it while the system accent is Multicolor. |
| Toggled pill | rgba(255,255,255,0.12) | rgba(0,0,0,0.08) | Behind an active toolbar item (Info while the panel is open), 14 pt radius. |
| Feather mark | #FFC766 → #FF7A59, linear 0,0 → 1,1 | same | Only the empty-window hint and About. The one warm note in the app. |
| Histogram line / fill | accent / accent 0.14 | same | Info panel luminance histogram. |
| Histogram channels | rgb(255,105,105,0.85) · rgb(110,225,140,0.85) · rgb(120,170,255,0.9) | same | RGB mode: thin red, green, blue lines under the luminance. |
| Clip mark (off) | rgba(255,255,255,0.45) | rgba(0,0,0,0.45) | Outlined clip mark; filled in the accent when more than 0.1 % clips. |
| Tile fill | rgba(255,255,255,0.06) | rgba(0,0,0,0.05) | Info panel exposure tiles. |
| Chip fill / line | rgba(255,255,255,0.06) / 0.10 | rgba(0,0,0,0.04) / 0.10 | Info panel chips (exposure bias, flash, white balance, metering). |
| Focus ring | accent at 50 % (as the system's `keyboardFocusIndicatorColor`), 2 pt, 1 pt outside the shape | same | Keyboard focus in the info panel, shown whether or not keyboard navigation is on in System Settings; a click focuses without it. |

## Materials

| Surface | macOS 26 | macOS 14 / 15 | Notes |
|---|---|---|---|
| Toolbar groups, strip | `.glassEffect(.regular, in: .capsule)`, groups in one `GlassEffectContainer` | `NSVisualEffectView` `.hudWindow` (dark) / `.popover` (light), `.withinWindow`, masked to the capsule | Hairline on 14/15 only (glass draws its own edge on 26); E2 shadow on both. |
| Info panel | `.glassEffect(.regular, in: .rect(cornerRadius: 16))` | same material, 16 pt mask | Panel fill token on top of the material at 25 % to steady text over the picture edge. |
| Folder chooser, F7 sheet | `.glassEffect(.regular, in: .rect(cornerRadius: 16))` | `.hudWindow` / `.sheet` | Sheet fill token on top at 35 %. No dimming scrim behind: the picture stays readable. |
| Selected rows, key caps | Plain fills from the tokens (no glass inside glass). | same | Selection: accent at 100 %, on-accent text, 8–9 pt radius, as in system lists. |

## Elevation

One key light from above, two layers per level: a tight contact shadow that anchors the edge and a
wide ambient shadow that lifts the shape. Offset and blur grow by about 1.6× per level
(y : blur ≈ 1 : 2.5); only the alpha changes between appearances. Values are CSS
`0 y blur colour`.

| Level | Role | Dark | Light | Used by |
|---|---|---|---|---|
| E0 | Flat | none | none | Key caps, selected rows, toggled pills, tab pills, dark push buttons, pop-ups, badges, separators. |
| E1 | Raised control | 0 1 3 rgba(0,0,0,0.30) | 0 1 3 rgba(0,0,0,0.12) | Switch knobs; light-appearance push buttons and pop-ups. |
| E2 | Floating chrome | 0 1 2 rgba(0,0,0,0.20) + 0 6 16 rgba(0,0,0,0.30) | 0 1 2 rgba(0,0,0,0.06) + 0 6 16 rgba(0,0,0,0.10) | Toolbar groups, status strip. |
| E3 | Surface in the window | 0 2 4 rgba(0,0,0,0.22) + 0 12 32 rgba(0,0,0,0.34) | 0 2 4 rgba(0,0,0,0.07) + 0 12 32 rgba(0,0,0,0.14) | Fitted picture (plus hairline), info panel, message boxes. |
| E4 | Sheet / object above the surface | 0 4 8 rgba(0,0,0,0.26) + 0 20 48 rgba(0,0,0,0.40) | 0 4 8 rgba(0,0,0,0.08) + 0 20 48 rgba(0,0,0,0.18) | Folder chooser, Move to Folder, the app-icon tile in About. |
| E5 | Window | 0 8 16 rgba(0,0,0,0.28) + 0 32 72 rgba(0,0,0,0.45) | 0 8 16 rgba(0,0,0,0.10) + 0 32 72 rgba(0,0,0,0.22) | Mockups only; in the app the system draws window shadows. |

Shadows are always neutral black. Inset highlight and hairline belong to the glass recipe, not to
elevation. Reduce Transparency keeps the shadows and swaps glass for a solid fill.

## Typography (SF Pro, Dynamic Type off)

| Role | Size / line | Weight | Colour | Where / notes |
|---|---|---|---|---|
| Window title | 13 / 16 | Semibold | primary | File name only. Leading at x = 184, centred in the 52 pt title bar. |
| Title counter | 13 / 16 | Regular | secondary, tabular | " — 1 / 4" after the name, 6 pt gap. |
| Status strip | 11 / 14 | Regular | strip, tabular | Five items, 12 pt gap, 1 × 12 separators. Localised formatting as today. |
| Empty hint | 13 / 16 | Regular | secondary (0.70) | Centred under the 44 pt feather. |
| Key cap | 11 / 14 | Medium | key cap text | Padding 3 × 7, radius 5. Footer hints: padding 1 × 5, radius 4. F7 keys: 12 / 14 Semibold in a 22 × 22 square, radius 6. |
| Panel / sheet title | 15 / 20 | Semibold | primary (0.90) | Folder name, "Move to Folder"; file name in the info panel is 13 Semibold. |
| Row label | 13 / 16 | Regular | primary | Selected row: Medium, white. |
| Row value / count | 13 / 16 | Regular | secondary, tabular | Trailing-aligned. |
| Hint / caption | 11 / 14 | Regular | tertiary | Footer of chooser and F7, "end of folder", "F7", format badge (Medium 11). |
| Small button | 12 / 14 | Medium | primary | "Choose…": height 22, padding 0 × 10, radius 6, key-cap fill, hairline 0.12. |

## Window layout

| Part | Spec |
|---|---|
| Title bar | 52 pt tall, transparent, full-size content view: the picture scrolls beneath it. Traffic lights at 20 / 20, 12 pt circles, 8 pt gap (system). |
| Fit area | Insets leading 16 · top 60 · trailing 16 · bottom 44 (strip 28 + 8 inset + 8 clearance). A fitted picture is centred in it; with the info panel open the trailing inset becomes 12 + 280 + 16 = 308. |
| Picture | No corner radius, no border. Shadow + hairline only while it fits. At any zoom beyond fit it runs edge to edge under the glass and loses both; the system's scroll edge effect dims it under the toolbar. |
| Status strip | x 12, y 664, w 1196, h 28, capsule. With the info panel open it ends 16 pt before the panel (w 900). Leading-aligned text, 14 pt inner padding. |
| Window | 12 pt corner radius (system). Dark: 1 pt inset hairline rgba(255,255,255,0.07); light: rgba(0,0,0,0.08). |
| Resizing | Only the fit area and the strip width change. Toolbar groups keep their size; the title truncates with an ellipsis before the counter does. |

## Toolbar

| Part | Spec |
|---|---|
| Leading group | Capsule 76 × 32 at x 96, y 10. Padding 2. Two items 36 × 28, radius 14. chevron.backward / chevron.forward, 13 pt Semibold. |
| Trailing group | Capsule 256 × 32, trailing inset 12 (x 952), y 10. Seven items 36 × 28 with two 1 × 16 separators: rotate ⟵ rotate ⟶ │ zoom out · fit · zoom in │ info · trash. |
| Glyphs | rotate.left, rotate.right, minus.magnifyingglass, arrow.up.left.and.down.right.magnifyingglass, plus.magnifyingglass, info.circle, trash. 15 pt Medium, label primary. |
| Hover | Item background rgba(255,255,255,0.08) / light rgba(0,0,0,0.05), 14 pt radius, 80 ms. |
| Pressed | Background 0.14 / 0.09, glyph scales to 0.94 (macOS 26: the glass does this). |
| Toggled on | Info while the panel is open: toggled-pill fill, glyph in the accent. |
| Disabled | Disabled-glyph token. Empty window: every item disabled, capsules remain. |
| Trash | Same colour as the others. |
| Share | `square.and.arrow.up`, tooltip "Share", between Info and Trash, in the default set; opens the system's share picker. |
| Rename field | A click on the file name (or F2) turns the title's name into a text field in place, in the window title's type, the part before the extension selected; a refusal shows in the window's message box. Dragging the title still moves the window. With the toolbar hidden or in full screen the same field shows in a small "Rename" sheet with Cancel / Rename. |

Implementation note: Featherview keeps the system toolbar (customizable, Hide Toolbar, on-hover in
full screen). macOS draws the capsules and their sizes; the separators inside the trailing capsule
are not available there and become the system's group gaps.

## Elements

| Element | Frame | Inside |
|---|---|---|
| Status strip | 1196 × 28 · x 12 · y 664 · capsule · glass fill · E2 | Padding 0 × 14; items: pixel size · zoom % · file size · position · date; gap 12; separators 1 × 12 (0.16 dark). Strip token, 11 Regular, tabular. |
| Empty hint card | 300 × 168 · centred in the fit area · radius 18 · flat, not glass: card fill and card line (the info panel's), E0 | Padding 24 × 28, column, gap 12: feather 44 × 44 (no tile) · hint 13 Regular secondary · key caps ⌘O and O, gap 6. Toolbar disabled; no strip. |
| Info panel (I) | 280 wide, full fit-area height · trailing inset 12 · radius 16 · panel fill · E3 | Design B2-1b-2 (<https://claude.ai/artifact/Lf6bXo8PaC2Exi6A6Unvmx>), see "Info panel" below. Padding 16, column, gap 10, scrolls as a whole. Slides in from trailing 180 ms; picture and strip refit in the same animation. |
| Folder chooser | 400 wide · centred in the fit area · radius 16 · sheet fill · E4 | Padding 16, column, gap 12. Header 20 tall: folder glyph 16 secondary · folder name 15 Semibold · trailing caption "end of folder" tertiary. Rows 40 tall, radius 9, padding 0 × 12, gap 10: glyph 16 · label 13 · count secondary tabular. Highlighted row: accent fill, on-accent label Medium, count on-accent 0.75. Footer: key caps → ← ↩ esc with their verbs, 11 tertiary, separated by 1 × 10 lines. |
| Move to Folder (F7 / F8) | 480 wide · centred in the fit area · radius 16 · sheet fill · E4 | Padding 16, column, gap 12. Header 20 tall: "Move to Folder" 15 Semibold · trailing "F7" tertiary (F8: "Copy to Folder" / "F8"). 14 rows × 32, radius 8, padding 0 6 0 5, gap 10: key cap 22 × 22 · label 13 (folder primary, "Empty" tertiary) · "Choose…" 22 tall. Highlighted row: accent fill; key cap and button on-accent fills (white 0.22 / 0.20 in light, black 0.14 / 0.12 in dark) with on-accent text. Footer hint 11 tertiary with ↩ and esc key caps. |
| Slideshow controls (full screen) | auto × 36 · centred · 24 above the bottom edge · radius 18 · glass fill · E3 | Padding 4, row, gap 4: four borderless items 36 × 28 — chevron.backward · play.fill / pause.fill · chevron.forward (13 Semibold) · xmark (15 Medium), label primary. Shows when the pointer moves, fades out after 2 s at rest unless the pointer is over it (in 120 ms, out 200 ms, opacity only); the pointer hides with it when "Hide the pointer" is on. Paused or finished, it stays up with play. Not shown while playing in the window. |
| Key caps | auto × 20 · radius 5 (footer: 4) | Key-cap token. ⌘ and arrows as text (→ ← ↑ ↩), "esc" lower case. Never an icon font. |

## Info panel

Design B2-1b-2 (canvas <https://claude.ai/artifact/Lf6bXo8PaC2Exi6A6Unvmx>, board "B2-1b-2 · Dark (main)");
behaviour in `docs/spec.md` "Info panel".

| Part | Spec |
|---|---|
| Header | 4 pt side padding, lines 2 apart: file name 13 Semibold title colour, cut in the middle, full name as tooltip; format line 11 secondary tabular ("JPEG · 3,000 × 2,000 · 476 KB"); with a place, 3 below: accent pin + short place 11 primary, up to two lines. |
| Histogram | "Histogram" 11 Semibold secondary and the Luminance / RGB control trailing (segments 10 Medium, padding 2 × 7, radius 5; on segment toggled-pill fill, accent text; track card fill, radius 6, padding 2). Plot 60 tall, full width, card fill, card line, radius 6, quarter grid lines (row separator). Luminance: 1.5 pt accent line over an accent 0.14 fill; RGB adds 1 pt channel lines under it. Clip marks: 11 × 10 triangles 3 pt in from the bottom corners, outlined (clip mark off, 1.2 pt) or filled accent; a click shows "Highlights: 2.4 % clipped" in a small bubble (11, background colour, chip line, radius 4) at the top of the plot. HDR: dashed 1.0 marker at 1 / headroom of the width, a 10 pt scale row under the plot ("1.0" at the marker, "3.2×" trailing). The plot never mirrors. |
| Groups | Cards: card fill, card line, radius 10. Header 36 tall, padding 0 × 12, gap 7: accent glyph · title 12 Semibold · closed summary 12 secondary tabular, trailing, one line · chevron (forward closed, down open) secondary. Order Camera, Image, Location, Description, File; empty groups left out. |
| Rows | 32 tall, padding 0 × 12, 1 pt separator above each (row separator), label 12 secondary · value 12 primary tabular, trailing, one line cut in the middle with the full value as tooltip; Description's texts wrap (9 pt vertical padding). |
| Tiles | Camera, inset 2 × 8 (10 bottom): four tiles 4 apart, tile fill, radius 8, padding 6 × 2 × 5: number 14 Semibold primary tabular (shrinks to 0.8), under it accent glyph + unit 10 secondary. Shutter "sec" with a timer glyph, aperture "ƒ stop", ISO "ISO speed", focal length "mm" with a lens glyph. |
| Chips | 8 under the tiles, wrapping, 5 apart: capsule, chip fill and line, padding 3 × 8, accent glyph + text 11 primary. |
| Place line | Location's first line: full place 13 Semibold primary, up to two lines, padding 0 × 12, 9 below. |
| Buttons | "Open in Maps" (map glyph), "Show in Finder" (folder glyph) in a trailing row of their group; "Show all metadata…" leading at the bottom. Small button: 22 tall, padding 0 × 10, radius 6, key-cap fill, hairline 0.12, glyph + 12 Medium. |
| Keyboard | Tab from the picture enters at the mode control (⇧Tab at "Show all metadata…"); order: mode, clip marks, each group header with its open group's button, "Show all metadata…"; past either end and Esc go back to the picture. The focused control shows the focus ring and scrolls into view. |

## Motion

| Topic | Spec |
|---|---|
| Principle | Animation explains a state change, never decorates. Nothing between a key press and the next picture. Ceiling 200 ms (About glow 300 ms). Ease-out for arrivals, ease-in-out for movement, linear for opacity. |
| Browsing | 0 ms, no crossfade; title and strip update in the same frame. Strip text fades 120 ms only when a different file arrives, never on zoom. |
| Zoom | 120 ms ease-out, anchored at the cursor (centre from the keyboard), Fit included. Pinch: no easing. E3 shadow and hairline off at the first frame beyond fit. |
| Rotation | 160 ms ease-in-out about the picture centre; repeated presses chain. |
| Info panel | 180 ms ease-in-out: slides 24 pt from the trailing edge while fading 0 → 1; picture and strip refit on the same curve. The toolbar toggle does not animate. |
| Sheets | Chooser and F7: 160 ms, scale 0.97 → 1 with fade; close 120 ms reverse. No overshoot. |
| Move / Trash | With "show the next image": the leaving picture fades out 60 ms, the next appears hard. |
| Bars at rest | After 2 s without input while browsing, toolbar groups and strip fade to 0 in 200 ms, opacity only (traffic lights and title stay). Mouse move or key: back in 120 ms. Panels and sheets never fade. |
| Hover / press | 80 ms fill change; macOS 26 glass press response. Toggled and disabled states switch without animation. |
| Loading | No indicator before 150 ms; then a system spinner centred in the fit area, or the previous picture dimmed to 0.5. |
| Drop target | 2 pt accent outline around the fit area, fades 120 ms in and out while something is dragged over. |
| Never | Crossfades or slides between pictures; Ken Burns, parallax, bounce beyond the system rubber band; springs on panels or sheets; eased pinch zoom; animated toolbar glyphs; morphing title text; feather flourishes beyond the About fade. |
| Reduce Motion | Zoom, rotation, panel and sheet durations become 0. Pure opacity changes (bars, strip fade, drop outline, About glow) stay. |

## Direction, states, consistency

| Topic | Spec |
|---|---|
| RTL | Back/forward group, title and trailing group swap sides; glyph order reverses; chevrons flip. Info panel opens from the leading edge. Strip text trailing-aligned. The picture is never mirrored. |
| Window inactive | Glyphs drop to secondary; glass keeps its fill. |
| Full screen | Same chrome, same insets; bars fade as above. Background fills the screen. |
| Settings | 560 wide, the app's appearance. Viewer › Appearance: three 128 × 82 miniature viewer windows (System split corner to corner, Light, Dark), radius 8, chosen one with a 3 pt accent ring and its name semibold in the accent. Header 96: pane title 13 Semibold in the top 40; tab row of 72 × 46 pills (gap 4), glyph 22 + label 11 Medium, selected pill 0.10 / 0.07 with accent glyph and label. Content padding 22 × 24, sections 22 apart: header 13 Semibold, 8 gap, card radius 10, rows 44 (52 two-line), padding 0 × 14, inset separators. Push buttons 28 radius 7; pop-ups 26 with accent chevron square 16 × 16 radius 4; switches 38 × 22, system. Browsing › Default app: one row per common type, its current app secondary and a "Use Featherview" push button trailing. |
| About | 320 × 440, close button only, the app's appearance, never restored at launch. Icon tile 128, radius 28.8, gradient #23232C → #101015, E4. Behind it a 280 pt radial glow in the feather colours (0.26 → 0 dark, 0.45 → 0 light). Name 22 / 28 Semibold, tagline 13 secondary, "Version" tertiary with the build in a key cap (tabular), hairline, copyright 11 tertiary, two accent links 11. Featherview keeps About's other content (Report a Problem, formats, licence) below the hairline. |
| Update notice | 480 wide, About's background, close button only, never restored. 44 pt feather mark leading, 12 gap; title 15 Semibold, "You have …" secondary 6 below; release notes in a card (radius 10, Settings card fill and line) 180 tall, scrolling; Skip This Version leading, Later and Download (default) trailing. Padding 40 / 24 / 20 / 24. |
| Accessibility · focus | Info panel controls take the keyboard whether or not keyboard navigation is on and show the focus ring (accent at 50 %, 2 pt, 1 pt outside the shape) only while the keyboard focused them, never after a click. |
| Accessibility · Increase Contrast | Info panel: secondary text becomes primary, hairlines (card lines, separators, grid) 1.5 pt. Also with Differentiate Without Colour. |
| Accessibility · Reduce Motion | Info panel groups open and close as a cut; scrolling to the focused control jumps. |
| Batch window | Three columns stay. Sidebar rows 32 tall, 8 pt radius, selected row accent with on-accent text; "on" badges secondary tabular; cards as in Settings. |
