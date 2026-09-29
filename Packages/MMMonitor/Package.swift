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
    ],
    targets: [
        .target(
            name: "MMMonitor",
            dependencies: ["MMCore"]
        ),
    ]
)
