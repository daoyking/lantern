// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lantern",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Lantern",
            path: "Sources/Lantern"
        ),
        .testTarget(
            name: "LanternTests",
            dependencies: ["Lantern"],
            path: "Tests/LanternTests"
        )
    ]
)
