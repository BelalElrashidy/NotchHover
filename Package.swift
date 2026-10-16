// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchHover",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotchHover",
            path: "Sources"
        )
    ]
)
