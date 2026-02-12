// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NanoBananaDesktop",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NanoBananaDesktop", targets: ["NanoBananaDesktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.99.0")
    ],
    targets: [
        .executableTarget(
            name: "NanoBananaDesktop",
            path: "NanoBananaDesktop",
            exclude: [
                "Tests",
                "NanoBananaDesktop.xcodeproj",
                "project.yml"
            ],
            resources: [
                .process("Resources/Localizations")
            ]
        ),
        .testTarget(
            name: "NanoBananaDesktopTests",
            dependencies: [
                "NanoBananaDesktop",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "NanoBananaDesktop/Tests"
        )
    ]
)
