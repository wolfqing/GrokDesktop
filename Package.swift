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
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.19.0")
    ],
    targets: [
        .target(
            name: "GrokDesktopCore",
            path: "Sources/GrokDesktopCore"
        ),
        .executableTarget(
            name: "GrokDesktop",
            dependencies: [
                "GrokDesktopCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/GrokDesktop"
        ),
        .executableTarget(
            name: "GrokDesktopSmoke",
            dependencies: ["GrokDesktopCore"],
            path: "Sources/GrokDesktopSmoke"
        )
    ]
)
