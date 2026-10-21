# Featherview

A fast, lightweight, keyboard-driven image viewer for macOS, with batch conversion.

**[Download](https://github.com/featherview/featherview/releases/latest)** · [Website](https://featherview.mynetx.net)

- Opens instantly and flips through every image in the folder with the arrow keys
- Opens everything macOS can read (JPEG, PNG, HEIC, AVIF, JPEG XL, WebP, TIFF, GIF, BMP, PSD,
  JPEG 2000, TGA, OpenEXR, DNG and camera RAW), upright and colour-managed
- Shows SVG, and PDF pages like a multi-page image
- Also reads formats macOS can't: QOI, PCX/DCX, XBM, XPM, WBMP, Sun Raster, IFF/LBM (including HAM),
  MacPaint, PAM, farbfeld, X Window Dump, FITS (astronomy), Windows animated cursors (first frame),
  Kodak Photo CD (at 768 × 512), JPEG XR (HD Photo) and BPG
- Shows layered files from image editors flattened: Photoshop PSB, GIMP XCF, Paint.NET PDN,
  PaintShop Pro PSP, Krita KRA and OpenRaster ORA (their stored flattened image), and Procreate (at
  full size, turned the way the canvas was). Blend modes other than normal are drawn as normal; PSB
  files without a stored composite, multichannel PSB and GIMP layer effects aren't shown; `.xcf.gz` isn't read
- Finder thumbnails and Quick Look (Space) previews for the formats macOS can't read, with a
  proper Kind name for each
- HDR photos (iPhone HEIC and JPEG, HDR AVIF, OpenEXR) show their extra brightness on HDR screens
  (macOS 15 and later)
- Saves and batch converts to JPEG, PNG, HEIC, AVIF, TIFF, WebP, GIF, BMP, JPEG 2000, PDF, PSD, TGA,
  ICO, ICNS, OpenEXR, PBM, PGM, PPM, QOI and PCX
- Lossless JPEG/HEIC/TIFF rotation
- Batch convert and rename with crop, resize, rotate, colour, filters, canvas, border, text and
  watermark steps, a live preview and presets
- EXIF info panel; delete moves to Trash
- In 30 languages, with right-to-left layout in Arabic and Hebrew

Status: public preview (0.9), on the way to 1.0. Requires macOS 14 (Sonoma) or later.

## Third-party code

- [libwebp](https://chromium.googlesource.com/webm/libwebp) 1.6.0 (BSD-3-Clause), for writing WebP,
  built from source through [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode).
- [jxrlib](https://github.com/4creators/jxrlib) (BSD-2-Clause, Microsoft), for reading JPEG XR,
  vendored in `Sources/CJPEGXR` from [Tom94/jxrlib](https://github.com/Tom94/jxrlib) (Debian's
  patches applied) and built from source by SwiftPM.

## Install

Download `Featherview-<version>.dmg` from the
[latest release](https://github.com/featherview/featherview/releases/latest), open it and drag `Featherview.app` to
`Applications`.
Or with Homebrew: `brew install --cask featherview/tap/featherview`.

Featherview is free and not notarized by Apple (that needs a paid developer account), so macOS
blocks the first launch. To open it anyway:

1. Double-click Featherview. macOS says it can't verify the app; click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down to the message about Featherview and
   click **Open Anyway**. Confirm with your password or Touch ID.
3. From now on it opens normally. After this first open, Finder shows thumbnails and Quick Look
   previews for the formats only Featherview reads (switches in System Settings → General → Login
   Items & Extensions → Quick Look).

Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Featherview.app`

Want to help? Sponsoring the $99/year Apple Developer Program would let us sign and notarize
releases, so none of this is needed.

## Updates

Featherview tells you when a newer version is out; it never downloads or installs anything itself.

- **How it checks:** about 10 seconds after launch, at most once a day, it reads a small feed at
  `https://featherview.mynetx.net/appcast.xml`. That's a plain web request with no cookies and
  nothing about you or your Mac beyond the request itself (its User-Agent says `Featherview/<version>`).
  If the check fails, nothing is shown and it tries again at a later launch.
- **What you see:** a small window, "Featherview 1.2.0 is available", with "You have 1.1.0." and
  what's new. **Download** has your browser download the new disk image; **Skip This Version** stops the
  notice for that version (a later one shows again); **Later** asks again at the next check.
- **By hand:** Featherview › Check for Updates… checks right away and also tells you when you're up
  to date.
- **Turn it off:** Preferences › Browsing › "Check for updates automatically".

## Build

Requires Xcode (full install, not only the Command Line Tools).

```sh
scripts/bundle.sh
open build/Featherview.app
```

Disk image: `scripts/dmg.sh` writes `build/Featherview-<version>.dmg`.

## License

MIT, see [LICENSE](LICENSE).

## Disclaimer

Featherview is an independent, clean-room project inspired by the workflow of classic Windows
image viewers such as IrfanView. It is not affiliated with, endorsed by, or derived from
IrfanView or its author.

Thanks to Irfan Škiljan, whose viewer has shown for decades how fast looking at images can be.
