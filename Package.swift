// swift-tools-version:6.0
import PackageDescription

// libjxl's build settings, for its C (brotli) and C++ files alike.
let cjpegxlDefines = [("JPEGXL_ENABLE_SKCMS", "1"), ("JPEGXL_ENABLE_TRANSCODE_JPEG", "0"), ("JPEGXL_ENABLE_BOXES", "1")]
let cjpegxlHeaderPaths = ["libjxl", "libjxl/lib", "highway", "brotli/include", "skcms"]

let package = Package(
    name: "Featherview",
    platforms: [.macOS(.v14)],
    products: [
        // Decode and browse timings without a window; not part of the app bundle.
        .executable(name: "featherview-bench", targets: ["FeatherviewBench"]),
        // The disk image background per language, for scripts/dmg.sh; not part of the app bundle.
        .executable(name: "featherview-dmg", targets: ["FeatherviewDMG"]),
    ],
    dependencies: [
        // libwebp (BSD), compiled from Google's C sources by SwiftPM; only WebPEncoder uses it.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0"),
    ],
    targets: [
        // Everything testable without a window: scanning, decoding, caching, metadata, rotation, batch.
        .target(name: "FeatherviewCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode"), "CJPEGXR"]),
        // JPEG XL writing (libjxl). Only the app links it, so the Finder and Quick Look extensions stay without libjxl:
        // every public and async symbol of FeatherviewCore survives dead-stripping. The app hands it to ImageEncoder.jxlEncoder.
        .target(name: "FeatherviewJXL", dependencies: ["FeatherviewCore", "CJPEGXL"]),
        // jxrlib (BSD-2-Clause, Microsoft), vendored from github.com/Tom94/jxrlib at 0e1337d (Debian's
        // patches applied, plus our fixes for damaged files, each marked `featherview:`); only JPEGXRDecoder uses it.
        // The encoder sources are there because the glue links them.
        .target(name: "CJPEGXR", exclude: ["jxrlib/LICENSE"],
                cSettings: [
                    .define("__ANSI__"), .define("DISABLE_PERF_MEASUREMENT"),
                    .headerSearchPath("jxrlib/common/include"), .headerSearchPath("jxrlib/image/sys"),
                    .headerSearchPath("jxrlib/jxrgluelib"),
                    .unsafeFlags(["-w", "-O2"]),  // third-party code: no warnings; optimised in debug too, for the tests
                ]),
        // libjxl 0.12.0 (BSD-3-Clause + patent grant) with highway (Apache-2.0 or BSD-3-Clause), brotli (MIT) and
        // skcms (BSD-3-Clause), vendored from github.com/libjxl/libjxl at v0.12.0 (a7a9c787; highway 457c8917,
        // brotli 028fb5a2, skcms 96d9171c), only what the encoder needs; only JXLEncoder uses it. Our own files
        // are the four headers CMake would generate (include/jxl/{jxl,jxl_cms,jxl_threads}_export.h, version.h).
        .target(name: "CJPEGXL",
                exclude: ["libjxl/LICENSE", "libjxl/PATENTS", "highway/LICENSE", "highway/LICENSE-BSD3",
                          "brotli/LICENSE", "skcms/LICENSE"],
                cSettings: cjpegxlDefines.map { .define($0.0, to: $0.1) } + cjpegxlHeaderPaths.map { .headerSearchPath($0) }
                    + [.unsafeFlags(["-w", "-O2"])],  // third-party code we don't edit: no warnings; optimised in debug too, for the tests
                cxxSettings: cjpegxlDefines.map { .define($0.0, to: $0.1) } + cjpegxlHeaderPaths.map { .headerSearchPath($0) }
                    + [.unsafeFlags(["-w", "-O2"])]),
        // The SwiftUI app. Thin: wires FeatherviewCore to windows, menus and keys.
        .executableTarget(name: "Featherview", dependencies: ["FeatherviewCore", "FeatherviewJXL"]),
        // Finder thumbnails. SwiftPM can't make app extensions: scripts/bundle.sh wraps this binary in an .appex.
        .executableTarget(name: "FeatherviewThumbnail", dependencies: ["FeatherviewCore"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        // Quick Look previews (Space); wrapped in an .appex by scripts/bundle.sh like the thumbnails.
        .executableTarget(name: "FeatherviewPreview", dependencies: ["FeatherviewCore"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .executableTarget(name: "FeatherviewBench", dependencies: ["FeatherviewCore"]),
        .executableTarget(name: "FeatherviewDMG", dependencies: ["FeatherviewCore"]),
        .testTarget(name: "FeatherviewCoreTests", dependencies: ["FeatherviewCore", "FeatherviewJXL"]),
        .testTarget(name: "FeatherviewBenchTests", dependencies: ["FeatherviewBench"]),
    ],
    cxxLanguageStandard: .cxx17
)
