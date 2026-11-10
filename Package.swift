// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glowdeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Glowdeck", targets: ["Glowdeck"]),
        .library(name: "GlowdeckCore", targets: ["GlowdeckCore"]),
    ],
    targets: [
        .target(
            name: "GlowdeckCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Glowdeck",
            dependencies: ["GlowdeckCore"]
        ),
        .testTarget(
            name: "GlowdeckCoreTests",
            dependencies: ["GlowdeckCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
