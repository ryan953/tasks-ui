// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DexUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DexKit"),
        .target(name: "LinearKit"),
        .executableTarget(name: "DexUI", dependencies: ["DexKit", "LinearKit"]),
        .testTarget(name: "DexKitTests", dependencies: ["DexKit"]),
        .testTarget(name: "LinearKitTests", dependencies: ["LinearKit"]),
        .testTarget(name: "DexUITests", dependencies: ["DexUI", "DexKit", "LinearKit"]),
    ]
)
