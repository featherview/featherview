# Changelog

## 0.12.1 – 2026-10-30

- Standard (non-admin) accounts can open Featherview again: the disk image has a "Read Me First" file with one Terminal line that opens it on any account, where Open Anyway failed.
- The disk image keeps its designed background on other Macs instead of a plain Finder window.
- About now says Featherview is free and links to GitHub Sponsors to help pay Apple's notarization fee, in every language.

## 0.12.0 – 2026-10-28

- A new info panel shows a histogram with clipping marks, an exposure card and foldable groups for the current picture.
- Geotagged pictures show their place name in the app's language, offline, with Open in Maps.
- Image › All Metadata opens a window with every tag in the file, searchable and fully keyboard-driven.
- The info panel takes the keyboard (Tab, Space, Return, Esc), and VoiceOver reads each row's label and value.
- The histogram handles HDR and 10-bit pictures correctly and never slows browsing.
- Web addresses in About's text sheets are now clickable.
- Plus smaller fixes, among them sturdier handling of odd GPS, XMP and exposure values in the info panel.

## 0.11.0 – 2026-10-26

- Featherview now updates itself: it checks for new versions and installs them with your OK.
- The thumbnail grid always fills the window with whole columns; `+`, `−` and pinch change the size by one column.
- Right-click a thumbnail for a menu; `⌘C` and Show in Finder work on the whole selection.
- Drag thumbnails out of the grid into Finder, Mail or other apps as files.
- Plus smaller fixes, among them drags out of the grid no longer being caught by Featherview's own drop targets.

## 0.10.1 – 2026-10-24

- Customized toolbars now survive a relaunch instead of resetting.
- Browsing on a second display stays fast, with images decoded in that screen's colour space.
- The thumbnail grid opens quicker for folders with thousands of files.
- Compare's first Difference view appears almost instantly.

## 0.10.0 – 2026-10-24

- Press `T` for a thumbnail grid of the folder. Move, copy, Trash, batch and Quick Look work on the selection.
- Compare two images side by side, zoom and pan them in step, and see their difference.
- Play a slideshow in the window or in full screen, and play animated images (`G` pauses).
- Rename the image from the window title with `F2`, and refresh the folder with `F5`. Follow New Files shows images as they arrive.
- Flip with `H` and `V`, zoom to width or height with `2` and `3`, and sort the folder by name, date or size.
- Save As and batch can write JPEG XL. Batch can also split images into tiles, write every frame or page, and set the date taken.
- Security: a damaged or crafted JPEG XR file can no longer crash Featherview or read memory it shouldn't.
- Plus smaller fixes, among them HDR photos keeping their gain map when saved as HEIC or AVIF, and rotating HEIC photos losslessly.

## 0.9.0 – 2026-10-21

- Flip through every image in a folder with the arrow keys; images open instantly.
- Opens JPEG, PNG, HEIC, AVIF, JPEG XL, WebP, RAW and many more, plus SVG and PDF pages.
- Reads layered files from Photoshop, GIMP, Krita, Paint.NET and others as a flattened image.
- Batch convert and rename with crop, resize, rotate, colour, filters, text and watermark steps, live preview and presets.
- Save As and batch output to JPEG, PNG, HEIC, AVIF, WebP, TIFF, PDF and more.
- Finder thumbnails and Quick Look previews for formats macOS can't show itself.
- Lossless rotation, an EXIF info panel, and delete that moves files to the Trash.
- Available in 30 languages, including right-to-left layout; tells you when a new version is out.
