// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMDisk",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMDisk", targets: ["MMDisk"]),
    ],    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMUI"),
        .package(path: "../../Packages/MMFileScanner"),
    ],
    targets: [
        .target(
            name: "MMDisk",
            dependencies: ["MMCore", "MMUI", "MMFileScanner"]
        ),
        .testTarget(
            name: "MMDiskTests",
            dependencies: ["MMDisk"],
            path: "Tests/MMDiskTests"
        ),
    ]
)
