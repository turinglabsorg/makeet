// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AvviCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AvviCore", targets: ["AvviCore"])],
    targets: [
        .target(name: "AvviCore", path: "Core"),
        .target(name: "AvviPersistence", dependencies: ["AvviCore"], path: "Shared", exclude: ["Assets.xcassets", "Theme.swift"]),
        .testTarget(name: "AvviCoreTests", dependencies: ["AvviCore", "AvviPersistence"], path: "Tests/AvviCoreTests")
    ]
)
