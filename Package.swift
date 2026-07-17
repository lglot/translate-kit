// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslateKit",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1")
    ],
    targets: [
        .executableTarget(
            name: "TranslateKit",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources",
            resources: [
                .process("../Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TranslateKitTests",
            dependencies: ["TranslateKit"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
