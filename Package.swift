// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchTune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchTune",
            path: "Sources/NotchTune"
        )
    ]
)
