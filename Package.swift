// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UsefulNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UsefulNotch", targets: ["UsefulNotch"])
    ],
    targets: [
        .executableTarget(
            name: "UsefulNotch",
            path: "Sources/UsefulNotch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
