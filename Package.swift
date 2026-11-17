// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NetworkMonitor", targets: ["NetworkMonitor"])
    ],
    targets: [
        .target(
            name: "NetworkMonitorCore",
            path: "Sources/NetworkMonitorCore",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: ["NetworkMonitorCore"],
            path: "Sources/NetworkMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts")
            ]
        ),
        .testTarget(
            name: "NetworkMonitorTests",
            dependencies: ["NetworkMonitorCore"],
            path: "Tests/NetworkMonitorTests"
        )
    ]
)
