// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiskLens",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DiskLens", targets: ["DiskLens"]),
        .executable(name: "DiskLensChecks", targets: ["DiskLensChecks"]),
    ],
    targets: [
        .target(
            name: "DiskLensCore"
        ),
        .executableTarget(
            name: "DiskLens",
            dependencies: ["DiskLensCore"]
        ),
        .executableTarget(
            name: "DiskLensChecks",
            dependencies: ["DiskLensCore"]
        ),
    ]
)
