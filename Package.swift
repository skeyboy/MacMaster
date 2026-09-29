// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMaster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacMaster", targets: ["MacMaster"]),
    ],
    dependencies: [
        .package(path: "Packages/MMCore"),
        .package(path: "Packages/MMUI"),
        .package(path: "Packages/MMFileScanner"),
        .package(path: "Packages/MMCleaner"),
        .package(path: "Packages/MMUninstaller"),
        .package(path: "Packages/MMDisk"),
        .package(path: "Packages/MMMonitor"),
        .package(path: "Packages/MMGuardian"),
        .package(path: "Packages/MMOptimizer"),
    ],
    targets: [
        .executableTarget(
            name: "MacMaster",
            dependencies: [
                "MMCore",
                "MMUI",
                "MMFileScanner",
                "MMCleaner",
                "MMUninstaller",
                "MMDisk",
                "MMMonitor",
                "MMGuardian",
                "MMOptimizer",
            ],
            path: "Sources/MacMaster"
        ),
    ]
)
