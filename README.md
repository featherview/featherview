# Featherview

A fast, lightweight, keyboard-driven image viewer for macOS, with batch conversion.

- Opens instantly and flips through every image in the folder with the arrow keys
- Opens everything macOS can read (JPEG, PNG, HEIC, AVIF, JPEG XL, WebP, TIFF, GIF, BMP, PSD,
  JPEG 2000, TGA, OpenEXR, DNG and camera RAW), upright and colour-managed
- Shows SVG, and PDF pages like a multi-page image
- Also reads formats macOS can't: QOI, PCX/DCX, XBM, XPM, WBMP, Sun Raster and IFF/LBM (including HAM)
- Shows layered files from image editors flattened: Photoshop PSB, GIMP XCF, Paint.NET PDN and
  PaintShop Pro PSP. Blend modes other than normal are drawn as normal; PSB files without a stored
  composite, multichannel PSB and GIMP layer effects aren't shown; `.xcf.gz` isn't read
- HDR photos (iPhone HEIC and JPEG, HDR AVIF, OpenEXR) show their extra brightness on HDR screens
  (macOS 15 and later)
- Saves and batch converts to JPEG, PNG, HEIC, AVIF, TIFF, WebP, GIF, BMP, JPEG 2000, PDF, PSD, TGA,
  ICO, ICNS, OpenEXR, PBM, PGM, PPM, QOI and PCX
- Lossless JPEG/HEIC/TIFF rotation
- Batch convert, resize and rename
- EXIF info panel; delete moves to Trash

Status: early development. Requires macOS 14 or later.

## Third-party code

- [libwebp](https://chromium.googlesource.com/webm/libwebp) 1.6.0 (BSD-3-Clause), for writing WebP,
  built from source through [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode).

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
