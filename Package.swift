// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DroidMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DroidMacCore", targets: ["DroidMacCore"]),
        .executable(name: "DroidMacCLI", targets: ["DroidMacCLI"]),
        .executable(name: "DroidMac", targets: ["DroidMacApp"])
    ],
    targets: [
        .target(
            name: "DroidMacCore",
            dependencies: []
        ),
        .executableTarget(
            name: "DroidMacCLI",
            dependencies: ["DroidMacCore"]
        ),
        .executableTarget(
            name: "DroidMacApp",
            dependencies: ["DroidMacCore"]
        ),
        .testTarget(
            name: "DroidMacCoreTests",
            dependencies: ["DroidMacCore"]
        )
    ]
)
