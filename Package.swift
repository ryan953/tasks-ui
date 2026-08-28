// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DexUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DexKit"),
        .executableTarget(name: "DexUI", dependencies: ["DexKit"]),
        .testTarget(name: "DexKitTests", dependencies: ["DexKit"]),
        .testTarget(name: "DexUITests", dependencies: ["DexUI", "DexKit"]),
    ]
)
