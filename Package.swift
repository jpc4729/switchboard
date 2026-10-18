// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Switchboard",
            path: "Sources/Switchboard"
        ),
        .testTarget(
            name: "SwitchboardTests",
            dependencies: ["Switchboard"],
            path: "Tests/SwitchboardTests"
        )
    ]
)
