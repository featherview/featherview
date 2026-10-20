// swift-tools-version:6.0
import PackageDescription

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
        // jxrlib (BSD-2-Clause, Microsoft), vendored from github.com/Tom94/jxrlib at 0e1337d (Debian's
        // patches applied); only JPEGXRDecoder uses it. The encoder sources are there because the glue links them.
        .target(name: "CJPEGXR", exclude: ["jxrlib/LICENSE"],
                cSettings: [
                    .define("__ANSI__"), .define("DISABLE_PERF_MEASUREMENT"),
                    .headerSearchPath("jxrlib/common/include"), .headerSearchPath("jxrlib/image/sys"),
                    .headerSearchPath("jxrlib/jxrgluelib"),
                    .unsafeFlags(["-w"]),  // third-party code we don't edit; its warnings are noise
                ]),
        // The SwiftUI app. Thin: wires FeatherviewCore to windows, menus and keys.
        .executableTarget(name: "Featherview", dependencies: ["FeatherviewCore"]),
        // Finder thumbnails. SwiftPM can't make app extensions: scripts/bundle.sh wraps this binary in an .appex.
        .executableTarget(name: "FeatherviewThumbnail", dependencies: ["FeatherviewCore"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        // Quick Look previews (Space); wrapped in an .appex by scripts/bundle.sh like the thumbnails.
        .executableTarget(name: "FeatherviewPreview", dependencies: ["FeatherviewCore"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .executableTarget(name: "FeatherviewBench", dependencies: ["FeatherviewCore"]),
        .executableTarget(name: "FeatherviewDMG", dependencies: ["FeatherviewCore"]),
        .testTarget(name: "FeatherviewCoreTests", dependencies: ["FeatherviewCore"]),
        .testTarget(name: "FeatherviewBenchTests", dependencies: ["FeatherviewBench"]),
    ]
)
