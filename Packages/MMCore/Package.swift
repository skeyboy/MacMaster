// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMCore", targets: ["MMCore"]),
    ],
    targets: [
        .target(
            name: "MMCore",
            dependencies: [],
            path: "Sources/MMCore"
        ),
        .testTarget(
            name: "MMCoreTests",
            dependencies: ["MMCore"],
            path: "Tests/MMCoreTests"
        ),
    ]
)
