// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMGuardian",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMGuardian", targets: ["MMGuardian"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMUI"),
    ],
    targets: [
        .target(
            name: "MMGuardian",
            dependencies: ["MMCore", "MMUI"]
        ),
        .testTarget(
            name: "MMGuardianTests",
            dependencies: ["MMGuardian"],
            path: "Tests/MMGuardianTests"
        ),
    ]
)
