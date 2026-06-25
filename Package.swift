// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GodotLauncher",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GodotLauncher", targets: ["GodotLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "GodotLauncher",
            path: "Sources/GodotLauncher",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "GodotLauncherTests",
            dependencies: ["GodotLauncher"],
            path: "Tests/GodotLauncherTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
