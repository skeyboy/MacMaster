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
    ],
    targets: [
        .target(
            name: "MMGuardian",
            dependencies: ["MMCore"]
        ),
    ]
)
