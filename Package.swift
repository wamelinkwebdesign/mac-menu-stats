// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MenuStats", targets: ["MenuStats"]),
        .executable(name: "MenuStatsProbe", targets: ["MenuStatsProbe"])
    ],
    targets: [
        .target(name: "CProcessStats"),
        .target(name: "MenuStatsCore", dependencies: ["CProcessStats"]),
        .executableTarget(name: "MenuStats", dependencies: ["MenuStatsCore"]),
        .executableTarget(name: "MenuStatsProbe", dependencies: ["MenuStatsCore"]),
        .testTarget(name: "MenuStatsCoreTests", dependencies: ["MenuStatsCore"])
    ]
)
