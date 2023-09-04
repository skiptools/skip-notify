// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "skip-notify",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
    .library(name: "SkipNotify", targets: ["SkipNotify"]),
    .library(name: "SkipNotifyKt", targets: ["SkipNotifyKt"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "0.6.4"),
        .package(url: "https://source.skip.tools/skip-unit.git", from: "0.1.0"),
        .package(url: "https://source.skip.tools/skip-lib.git", from: "0.2.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.14"),
    ],
    targets: [
    .target(name: "SkipNotify", plugins: [.plugin(name: "skippy", package: "skip")]),
    .target(name: "SkipNotifyKt", dependencies: [
        "SkipNotify",
        .product(name: "SkipUnitKt", package: "skip-unit"),
        .product(name: "SkipLibKt", package: "skip-lib"),
        .product(name: "SkipFoundationKt", package: "skip-foundation"),
    ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
    .testTarget(name: "SkipNotifyTests", dependencies: [
        "SkipNotify"
    ], plugins: [.plugin(name: "skippy", package: "skip")]),
    .testTarget(name: "SkipNotifyKtTests", dependencies: [
        "SkipNotifyKt",
        .product(name: "SkipUnitKt", package: "skip-unit"),
        .product(name: "SkipLibKt", package: "skip-lib"),
        .product(name: "SkipFoundationKt", package: "skip-foundation"),
        .product(name: "SkipUnit", package: "skip-unit"),
    ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
    ]
)
