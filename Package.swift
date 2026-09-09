// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlyphPrint",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GlyphPrint",
            targets: ["GlyphPrint"]
        ),
        .executable(
            name: "gprint",
            targets: ["GlyphPrintCLI"]
        )
    ],
    targets: [
        .target(
            name: "GlyphPrint",
            dependencies: [],
            path: "Sources/GlyphPrint"
        ),
        .executableTarget(
            name: "GlyphPrintCLI",
            dependencies: ["GlyphPrint"],
            path: "Sources/GlyphPrintCLI"
        ),
        .testTarget(
            name: "GlyphPrintTests",
            dependencies: ["GlyphPrint"],
            path: "Tests/GlyphPrintTests"
        )
    ]
)
