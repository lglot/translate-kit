// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranslateKit",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
    name: "translate-kit",
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
