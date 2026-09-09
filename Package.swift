// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AltTab",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AltTab", targets: ["AltTab"])
    ],
    targets: [
        .executableTarget(
            name: "AltTab",
            path: "Sources/AltTab"
        ),
        .testTarget(
            name: "AltTabTests",
            dependencies: ["AltTab"],
            path: "Tests/AltTabTests"
        )
    ]
)
