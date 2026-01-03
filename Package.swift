// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tts-swift",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "tts",
            dependencies: ["KeyboardShortcuts"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ttsTests",
            dependencies: ["tts", "KeyboardShortcuts"]
        )
    ]
)
