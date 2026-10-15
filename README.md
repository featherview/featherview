# Featherview

A fast, lightweight, keyboard-driven image viewer for macOS, with batch conversion.

- Opens instantly and flips through every image in the folder with the arrow keys
- Shows JPEG, PNG, HEIC, WebP, TIFF, GIF and camera RAW, upright and colour-managed
- Lossless JPEG/HEIC/TIFF rotation
- Batch convert, resize and rename
- EXIF info panel; delete moves to Trash

Status: early development. Requires macOS 14 or later.

## Build

Requires Xcode (full install, not only the Command Line Tools).

```sh
scripts/bundle.sh
open build/Featherview.app
```

## Disclaimer

Featherview is an independent, clean-room project inspired by the workflow of classic Windows
image viewers such as IrfanView. It is not affiliated with, endorsed by, or derived from
IrfanView or its author.
