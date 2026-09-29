// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MMCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MMCleaner", targets: ["MMCleaner"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MMCore"),
        .package(path: "../../Packages/MMFileScanner"),
    ],
    targets: [
        .target(
            name: "MMCleaner",
            dependencies: ["MMCore", "MMFileScanner"]
        ),
    ]
)
