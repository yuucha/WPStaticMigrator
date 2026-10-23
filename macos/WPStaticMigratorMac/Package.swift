// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WPStaticMigratorMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WPStaticMigratorMac", targets: ["WPStaticMigratorMac"]),
    ],
    targets: [
        .executableTarget(
            name: "WPStaticMigratorMac",
            path: "Sources/WPStaticMigratorMac"
        ),
    ]
)
