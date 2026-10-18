// swift-tools-version:5.9
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
