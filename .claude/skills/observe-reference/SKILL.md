---
name: observe-reference
description: Observe how the reference Windows image viewer behaves, black-box, in the maintainer's VMPal VM, and record it in docs/parity.md in our own words. Use when deciding how a Featherview feature should behave, when the spec is silent, or when asked to check parity with the reference viewer.
---

# Observe the reference viewer

Clean-room rules in `AGENTS.md` apply. In short: use it like a user, write down behaviour, copy nothing.

**Never:** download or install anything for it (the maintainer installs it), open its program
folder, read its help, INI or other bundled files, browse its website, capture the whole screen,
commit a screenshot, or copy its wording, icons or dialog layouts.

## Steps

1. `vmpal_status`; start the VM with `vmpal_start` if needed. Take a snapshot before a session
   that changes settings (`vmpal_take_snapshot`), so the VM can go back to defaults.
2. Put test images in the VM with `vmpal_exec` (e.g. PowerShell generating images, or copying
   ones the maintainer provides). Use our own images, never sample images bundled with the viewer.
3. Launch the viewer on a file; drive it with `vmpal_act` (keys, clicks), always with `mask`.
   Answer one question per probe: "what does End do?", "what happens at the last image?".
4. Capture only its window: `vmpal_screenshot` with `region` set to the window's bounds. Save
   images you need to keep under `research/screenshots/` (gitignored).
5. Add one row per behaviour to `docs/parity.md`: area, what happened (our words, no quoted UI
   text), what Featherview should do on the Mac, status `open`.
6. Report the new rows to the maintainer. Only they move an item into `docs/spec.md`.

Mac adaptation beats parity: if a behaviour clashes with Mac conventions (menus, ⌘ shortcuts,
Trash, full screen), note the Mac way in the Featherview column.
