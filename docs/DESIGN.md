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
2. **One glass recipe, three shapes.** Capsule (toolbar groups, status strip), 16 pt card (panels,
   sheets), 18 pt card (empty hint). Same fill, highlight and hairline everywhere.
3. **Numbers are quiet and aligned.** Everything numeric is secondary colour with tabular figures
   (SF Pro monospaced digits) so the strip and panels never jitter while browsing.

## Colour tokens

Every window follows the app's appearance (Preferences › Viewer › Appearance: System, Light, Dark);
toolbar, title bar and glass with it. Use system dynamic colours where one exists.

| Token | Dark (Graphite) | Light (Grey) | Use |
|---|---|---|---|
| Background | #1C1C20 (Graphite) | #E7E7EC (Grey) | Window and area behind the picture. |
| Glass fill | rgba(52,52,58,0.55) | rgba(255,255,255,0.60) | Toolbar groups, status strip, empty hint card. Behind it: blur 40, saturation 180 %. |
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
| Accent | #FF7A59 (feather coral) | #B8552B (feather brown) | The app's accent colour (`Resources/Assets.xcassets`, `NSAccentColorName`): selected row fill with white text, toggled-on toolbar glyph, switches, Preferences tab. macOS uses it while the system accent is Multicolor. |
| Toggled pill | rgba(255,255,255,0.12) | rgba(0,0,0,0.08) | Behind an active toolbar item (Info while the panel is open), 14 pt radius. |
| Feather mark | #FFC766 → #FF7A59, linear 0,0 → 1,1 | same | Only the empty-window hint and About. The one warm note in the app. |

## Materials

| Surface | macOS 26 | macOS 14 / 15 | Notes |
|---|---|---|---|
| Toolbar groups, strip | `.glassEffect(.regular, in: .capsule)`, groups in one `GlassEffectContainer` | `NSVisualEffectView` `.hudWindow` (dark) / `.popover` (light), `.withinWindow`, masked to the capsule | Hairline on 14/15 only (glass draws its own edge on 26); E2 shadow on both. |
| Info panel | `.glassEffect(.regular, in: .rect(cornerRadius: 16))` | same material, 16 pt mask | Panel fill token on top of the material at 25 % to steady text over the picture edge. |
| Folder chooser, F7 sheet | `.glassEffect(.regular, in: .rect(cornerRadius: 16))` | `.hudWindow` / `.sheet` | Sheet fill token on top at 35 %. No dimming scrim behind: the picture stays readable. |
| Empty hint card | `.glassEffect(.regular, in: .rect(cornerRadius: 18))` | same, 18 pt | Over a flat background the blur is invisible; the tokens carry the look. |
| Selected rows, key caps | Plain fills from the tokens (no glass inside glass). | same | Selection: accent at 100 %, white text, 8–9 pt radius, as in system lists. |

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
| E3 | Surface in the window | 0 2 4 rgba(0,0,0,0.22) + 0 12 32 rgba(0,0,0,0.34) | 0 2 4 rgba(0,0,0,0.07) + 0 12 32 rgba(0,0,0,0.14) | Fitted picture (plus hairline), info panel, empty hint card. |
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

Implementation note: Featherview keeps the system toolbar (customizable, Hide Toolbar, on-hover in
full screen). macOS draws the capsules and their sizes; the separators inside the trailing capsule
are not available there and become the system's group gaps.

## Elements

| Element | Frame | Inside |
|---|---|---|
| Status strip | 1196 × 28 · x 12 · y 664 · capsule · glass fill · E2 | Padding 0 × 14; items: pixel size · zoom % · file size · position · date; gap 12; separators 1 × 12 (0.16 dark). Strip token, 11 Regular, tabular. |
| Empty hint card | 300 × 168 · centred in the fit area · radius 18 · glass fill · E3 | Padding 24 × 28, column, gap 12: feather 44 × 44 (no tile) · hint 13 Regular secondary · key caps ⌘O and O, gap 6. Toolbar disabled; no strip. |
| Info panel (I) | 280 × 596 · trailing inset 12 · y 60 · radius 16 · panel fill · E3 | Padding 16, column, gap 12. Header 24 tall, 4 pt side padding: file name 13 Semibold, ellipsis; format badge 11 Medium (fill 0.08, line 0.12, radius 4). Rows in a 10 pt card (fill 0.04, line 0.06): rows 40 tall, padding 0 × 12, label primary · value secondary tabular, 1 pt inset separators. Slides in from trailing 180 ms; picture and strip refit in the same animation. |
| Folder chooser | 400 wide · centred in the fit area · radius 16 · sheet fill · E4 | Padding 16, column, gap 12. Header 20 tall: folder glyph 16 secondary · folder name 15 Semibold · trailing caption "end of folder" tertiary. Rows 40 tall, radius 9, padding 0 × 12, gap 10: glyph 16 · label 13 · count secondary tabular. Highlighted row: accent fill, white label Medium, count 0.75 white. Footer: key caps → ← ↩ esc with their verbs, 11 tertiary, separated by 1 × 10 lines. |
| Move to Folder (F7 / F8) | 480 wide · centred in the fit area · radius 16 · sheet fill · E4 | Padding 16, column, gap 12. Header 20 tall: "Move to Folder" 15 Semibold · trailing "F7" tertiary (F8: "Copy to Folder" / "F8"). 14 rows × 32, radius 8, padding 0 6 0 5, gap 10: key cap 22 × 22 · label 13 (folder primary, "Empty" tertiary) · "Choose…" 22 tall. Highlighted row: accent fill; key cap and button white 0.22 / 0.20 with white text. Footer hint 11 tertiary with ↩ and esc key caps. |
| Key caps | auto × 20 · radius 5 (footer: 4) | Key-cap token. ⌘ and arrows as text (→ ← ↑ ↩), "esc" lower case. Never an icon font. |

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
| Preferences | 560 wide, the app's appearance. Viewer › Appearance: three 128 × 82 miniature viewer windows (System split corner to corner, Light, Dark), radius 8, chosen one with a 3 pt accent ring and its name semibold in the accent. Header 96: pane title 13 Semibold in the top 40; tab row of 72 × 46 pills (gap 4), glyph 22 + label 11 Medium, selected pill 0.10 / 0.07 with accent glyph and label. Content padding 22 × 24, sections 22 apart: header 13 Semibold, 8 gap, card radius 10, rows 44 (52 two-line), padding 0 × 14, inset separators. Push buttons 28 radius 7; pop-ups 26 with accent chevron square 16 × 16 radius 4; switches 38 × 22, system. "Use Featherview for Images" carries the 14 pt feather mark. |
| About | 320 × 440, close button only, the app's appearance, never restored at launch. Icon tile 128, radius 28.8, gradient #23232C → #101015, E4. Behind it a 280 pt radial glow in the feather colours (0.26 → 0 dark, 0.45 → 0 light). Name 22 / 28 Semibold, tagline 13 secondary, "Version" tertiary with the build in a key cap (tabular), hairline, copyright 11 tertiary, two accent links 11. Featherview keeps About's other content (Report a Problem, formats, licence) below the hairline. |
| Batch window | Three columns stay. Sidebar rows 32 tall, 8 pt radius, selected row accent with white text; "on" badges secondary tabular; cards as in Preferences. |
