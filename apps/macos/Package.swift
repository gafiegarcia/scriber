// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Scriber",
    platforms: [.macOS(.v15)],
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
