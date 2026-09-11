// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LyricBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LyricBar",
            path: "Sources/LyricBar"
        )
    ]
)
