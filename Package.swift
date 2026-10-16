// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakeetCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MakeetCore", targets: ["MakeetCore"])],
    targets: [
        .target(name: "MakeetCore", path: "Core"),
        .target(name: "MakeetPersistence", dependencies: ["MakeetCore"], path: "Shared", exclude: ["Assets.xcassets", "Theme.swift"]),
        .testTarget(name: "MakeetCoreTests", dependencies: ["MakeetCore", "MakeetPersistence"], path: "Tests/MakeetCoreTests")
    ]
)
