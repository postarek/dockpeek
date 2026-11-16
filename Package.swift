// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DockPeek",
    platforms: [.macOS(.v14)],
    targets: [
        // Also compiled directly into the System Settings pane by build.sh.
        .target(
            name: "DockPeekShared",
            path: "Sources/DockPeekShared"
        ),
        .executableTarget(
            name: "DockPeek",
            dependencies: ["DockPeekShared"],
            path: "Sources/DockPeek"
        ),
    ]
)
