# Featherview

A fast, lightweight, keyboard-driven image viewer for macOS, with batch conversion.

- Opens instantly and flips through every image in the folder with the arrow keys
- Shows JPEG, PNG, HEIC, WebP, TIFF, GIF and camera RAW, upright and colour-managed
- Lossless JPEG/HEIC/TIFF rotation
- Batch convert, resize and rename
- EXIF info panel; delete moves to Trash

Status: early development. Requires macOS 14 or later.

## Install

Download `Featherview.zip` from the releases page, unzip it and move `Featherview.app` to
`Applications`.

Featherview is free and not notarized by Apple (that needs a paid developer account), so macOS
blocks the first launch. To open it anyway:

1. Double-click Featherview. macOS says it can't verify the app; click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down to the message about Featherview and
   click **Open Anyway**. Confirm with your password or Touch ID.
3. From now on it opens normally.

Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Featherview.app`

Want to help? Sponsoring the $99/year Apple Developer Program would let us sign and notarize
releases, so none of this is needed.

## Build

Requires Xcode (full install, not only the Command Line Tools).

```sh
scripts/bundle.sh
open build/Featherview.app
```

## License

MIT, see [LICENSE](LICENSE).

## Disclaimer

Featherview is an independent, clean-room project inspired by the workflow of classic Windows
image viewers such as IrfanView. It is not affiliated with, endorsed by, or derived from
IrfanView or its author.

Thanks to Irfan Škiljan, whose viewer has shown for decades how fast looking at images can be.
