// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchLoft",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchLoft",
            path: "Sources/NotchLoft"
        )
    ]
)
