// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mac9PCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Mac9PCore", targets: ["Mac9PCore"]),
    ],
    targets: [
        .target(
            name: "Mac9PCore",
            dependencies: []
        ),
        .testTarget(
            name: "Mac9PCoreTests",
            dependencies: ["Mac9PCore"]
        ),
    ]
)

