// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchTools",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchTools",
            path: "Sources/NotchTools"
        )
    ]
)
