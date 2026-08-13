// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrokDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GrokDesktopCore", targets: ["GrokDesktopCore"]),
        .executable(name: "GrokDesktop", targets: ["GrokDesktop"])
    ],
    targets: [
        .target(
            name: "GrokDesktopCore",
            path: "Sources/GrokDesktopCore"
        ),
        .executableTarget(
            name: "GrokDesktop",
            dependencies: ["GrokDesktopCore"],
            path: "Sources/GrokDesktop"
        ),
        .executableTarget(
            name: "GrokDesktopSmoke",
            dependencies: ["GrokDesktopCore"],
            path: "Sources/GrokDesktopSmoke"
        )
    ]
)
