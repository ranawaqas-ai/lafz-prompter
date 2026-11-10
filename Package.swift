// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LafzPrompter",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "LafzPrompter",
            dependencies: ["HotKey"],
            path: "notch-prompter",
            // Compiled into the app bundle by scripts/build-app.sh with actool.
            exclude: ["Assets.xcassets"]
        ),
    ]
)
