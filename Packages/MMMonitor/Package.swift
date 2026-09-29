// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMMonitor", targets: ["MMMonitor"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMUI"),
    ],
    targets: [
        .target(
            name: "MMMonitor",
            dependencies: ["MMCore", "MMUI"]
        ),
        .testTarget(
            name: "MMMonitorTests",
            dependencies: ["MMMonitor"],
            path: "Tests/MMMonitorTests"
        ),
    ]
)
