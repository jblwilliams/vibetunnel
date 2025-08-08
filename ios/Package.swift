// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VibeTunnelDependencies",
    platforms: [
        .iOS(.v18),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "VibeTunnelDependencies",
            targets: ["VibeTunnelDependencies"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.2.5"),
        .package(url: "https://github.com/mhdhejazi/Dynamic.git", from: "1.2.0"),
        // TODO: Update to https://github.com/steipete/Tachikoma once https://github.com/steipete/Tachikoma/pull/3 is merged
        .package(url: "https://github.com/jblwilliams/Tachikoma", branch: "main")
    ],
    targets: [
        .target(
            name: "VibeTunnelDependencies",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Dynamic", package: "Dynamic"),
                .product(name: "Tachikoma", package: "Tachikoma"),
                .product(name: "TachikomaAudio", package: "Tachikoma")
            ],
            swiftSettings: [
                .swiftLanguageVersion(.v5)
            ]
        )
    ]
)
