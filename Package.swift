// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EyeWatch",
    platforms: [.macOS(.v13)],
    products: [.library(name: "EyeWatchCore", targets: ["EyeWatchCore"]), .executable(name: "EyeWatch", targets: ["EyeWatchApp"])],
    targets: [
        .target(name: "EyeWatchCore"),
        .executableTarget(name: "EyeWatchApp", dependencies: ["EyeWatchCore"]),
        .testTarget(name: "EyeWatchCoreTests", dependencies: ["EyeWatchCore"])
    ]
)
