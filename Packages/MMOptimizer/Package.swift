// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMOptimizer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMOptimizer", targets: ["MMOptimizer"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMUI"),
        .package(path: "../../Packages/MMFileScanner"),
    ],
    targets: [
        .target(
            name: "MMOptimizer",
            dependencies: ["MMCore", "MMUI", "MMFileScanner"]
        ),
        .testTarget(
            name: "MMOptimizerTests",
            dependencies: ["MMOptimizer"],
            path: "Tests/MMOptimizerTests"
        ),
    ]
)
