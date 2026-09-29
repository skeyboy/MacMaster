// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMUI", targets: ["MMUI"]),
    ],
    dependencies: [
        .package(path: "../MMCore"),
    ],
    targets: [
        .target(
            name: "MMUI",
            dependencies: ["MMCore"],
            path: "Sources/MMUI"
        ),
    ]
)
