// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslateKit",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/mattt/swift-toml.git", exact: "2.0.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", exact: "1.7.4")
    ],
    targets: [
        .target(
            name: "TranslateKitCore",
            dependencies: [
                .product(name: "TOML", package: "swift-toml"),
                .product(name: "AWSTranslate", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift")
            ],
            path: "Sources/TranslateKitCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "TranslateKitApple",
            dependencies: ["TranslateKitCore"],
            path: "Sources/TranslateKitApple",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "TranslateKit",
            dependencies: [
                "TranslateKitCore",
                "TranslateKitApple",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources",
            exclude: [
                "TranslateKitCore",
                "TranslateKitApple"
            ],
            resources: [
                .process("../Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TranslateKitTests",
            dependencies: ["TranslateKit", "TranslateKitCore", "TranslateKitApple"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
