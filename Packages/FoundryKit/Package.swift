// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FoundryKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FoundryFeatures", targets: ["FoundryFeatures"]),
    ],
    dependencies: [
        // Пре-1.0 — пиновать версию (practices 06 §1.1).
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "0.5.0"),
    ],
    targets: [
        .target(name: "FoundryCore"),
        .target(
            name: "FoundryCLI",
            dependencies: [
                "FoundryCore",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .target(
            name: "FoundryFeatures",
            dependencies: ["FoundryCore", "FoundryCLI"]
        ),
        .testTarget(name: "FoundryCoreTests", dependencies: ["FoundryCore"]),
        .testTarget(name: "FoundryCLITests", dependencies: ["FoundryCLI"]),
        .testTarget(name: "FoundryFeaturesTests", dependencies: ["FoundryFeatures"]),
    ]
)
