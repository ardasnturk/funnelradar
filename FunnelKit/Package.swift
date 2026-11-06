// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FunnelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FunnelKit", targets: ["FunnelKit"]),
        .executable(name: "funnelradar-hub", targets: ["funnelradar-hub"]),
    ],
    targets: [
        .target(name: "FunnelKit"),
        .executableTarget(name: "funnelradar-hub", dependencies: ["FunnelKit"]),
        .testTarget(name: "FunnelKitTests", dependencies: ["FunnelKit"]),
    ]
)
