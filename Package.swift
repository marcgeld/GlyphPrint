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
        ),
        .executable(
            name: "qr-example",
            targets: ["PrintQRCodeExample"]
        ),
        .executable(name: "photo-example", targets: ["PrintImageAndTextExample"])
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
        .executableTarget(
            name: "PrintQRCodeExample",
            dependencies: ["GlyphPrint"],
            path: "Examples/PrintQRCode"
        ),
        .executableTarget(
            name: "PrintImageAndTextExample",
            dependencies: ["GlyphPrint"],
            path: "Examples/PrintImageAndText",
            exclude: ["README.md"],
            resources: [.copy("markus-winkler-Z8yWSsx8OWE-unsplash.jpg")]
        ),
        .testTarget(
            name: "GlyphPrintTests",
            dependencies: ["GlyphPrint", "GlyphPrintCLI"],
            path: "Tests/GlyphPrintTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
