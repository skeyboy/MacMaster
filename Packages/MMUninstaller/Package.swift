// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMUninstaller",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMUninstaller", targets: ["MMUninstaller"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMFileScanner"),
        .package(path: "../../Packages/MMUI"),
    ],
    targets: [
        .target(
            name: "MMUninstaller",
            dependencies: ["MMCore", "MMFileScanner", "MMUI"]
        ),
        .testTarget(
            name: "MMUninstallerTests",
            dependencies: ["MMUninstaller"],
            path: "Tests/MMUninstallerTests"
        ),
    ]
)
