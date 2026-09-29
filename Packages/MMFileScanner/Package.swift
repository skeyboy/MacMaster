// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMFileScanner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMFileScanner", targets: ["MMFileScanner"]),
    ],
    dependencies: [
        .package(path: "../MMCore"),
    ],
    targets: [
        .target(
            name: "MMFileScanner",
            dependencies: ["MMCore"],
            path: "Sources/MMFileScanner"
        ),
        .testTarget(
            name: "MMFileScannerTests",
            dependencies: ["MMFileScanner"],
            path: "Tests/MMFileScannerTests"
        ),
    ]
)
