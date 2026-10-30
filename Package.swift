// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TodoBoard",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "BoardKit",
            path: "Sources/BoardKit"
        ),
        .target(
            name: "BoardUI",
            dependencies: ["BoardKit"],
            path: "Sources/BoardUI",
            resources: [.copy("Avatars")]
        ),
        .executableTarget(
            name: "TodoBoardApp",
            dependencies: ["BoardKit", "BoardUI"],
            path: "Sources/TodoBoardApp"
        ),
        .testTarget(
            name: "BoardKitTests",
            dependencies: ["BoardKit", "BoardUI"],
            path: "Tests/BoardKitTests"
        ),
    ]
)
