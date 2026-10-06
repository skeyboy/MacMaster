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
            // MMCore 是给 DiskRiskTests 用的：那份测试要直接点名 `DeletionGuard`，
            // 才能证明"标签与闸门同源"这句话不是注释里说说。
            dependencies: ["MMDisk", "MMCore"],
            path: "Tests/MMDiskTests"
        ),
    ]
)
