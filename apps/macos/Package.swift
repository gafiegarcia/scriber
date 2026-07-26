// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Scriber",
    // Matches the app target's deployment target so ScriberCore cannot compile
    // against an older SDK than the app that embeds its sources.
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ScriberCore", targets: ["ScriberCore"])
    ],
    targets: [
        .target(
            name: "ScriberCore",
            path: "ScriberCore"
        ),
        .testTarget(
            name: "ScriberCoreTests",
            dependencies: ["ScriberCore"],
            path: "ScriberCoreTests"
        )
    ]
)
