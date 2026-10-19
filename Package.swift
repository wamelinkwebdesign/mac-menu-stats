// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MenuStats", targets: ["MenuStats"]),
        .executable(name: "MenuStatsProbe", targets: ["MenuStatsProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "CProcessStats"),
        .target(name: "MenuStatsCore", dependencies: ["CProcessStats"]),
        .target(name: "MenuStatsAppControl", dependencies: ["MenuStatsCore"]),
        .executableTarget(
            name: "MenuStats",
            dependencies: [
                "MenuStatsCore",
                "MenuStatsAppControl",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(name: "MenuStatsProbe", dependencies: ["MenuStatsCore"]),
        .testTarget(name: "MenuStatsCoreTests", dependencies: ["MenuStatsCore"]),
        .testTarget(name: "MenuStatsAppControlTests", dependencies: ["MenuStatsAppControl"])
    ]
)
