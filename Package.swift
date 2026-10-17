// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Featherview",
    platforms: [.macOS(.v14)],
    products: [
        // Decode and browse timings without a window; not part of the app bundle.
        .executable(name: "featherview-bench", targets: ["FeatherviewBench"]),
    ],
    dependencies: [
        // libwebp (BSD), compiled from Google's C sources by SwiftPM; only WebPEncoder uses it.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0"),
    ],
    targets: [
        // Everything testable without a window: scanning, decoding, caching, metadata, rotation, batch.
        .target(name: "FeatherviewCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
        // The SwiftUI app. Thin: wires FeatherviewCore to windows, menus and keys.
        .executableTarget(name: "Featherview", dependencies: ["FeatherviewCore"]),
        .executableTarget(name: "FeatherviewBench", dependencies: ["FeatherviewCore"]),
        .testTarget(name: "FeatherviewCoreTests", dependencies: ["FeatherviewCore"]),
    ]
)
