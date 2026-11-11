// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LafzPrompter",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        // Tests only: approval files and view images (see notch-prompterTests/README.md).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "LafzPrompter",
            dependencies: ["HotKey"],
            path: "notch-prompter",
            // Compiled into the app bundle by scripts/build-app.sh with actool.
            exclude: ["Assets.xcassets"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LafzPrompterTests",
            dependencies: [
                "LafzPrompter",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "notch-prompterTests"
        ),
    ]
)
