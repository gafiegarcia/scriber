// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ScriberDictate",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScriberDictateCore", targets: ["ScriberDictateCore"])
    ],
    targets: [
        .target(
            name: "ScriberDictateCore",
            path: "ScriberDictateCore"
        ),
        .testTarget(
            name: "ScriberDictateTests",
            dependencies: ["ScriberDictateCore"],
            path: "ScriberDictateTests"
        )
    ]
)
