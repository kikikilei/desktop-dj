// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopDJ",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DesktopDJ", targets: ["DesktopDJ"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopDJ",
            path: "Sources/DesktopDJ"
        )
    ]
)
