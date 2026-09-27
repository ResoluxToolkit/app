// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Resolume",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/ResoluxCore"),
    ],
    targets: [
        .target(name: "Resolume", dependencies: [.product(name: "ResoluxCore", package: "ResoluxCore")]),
        .testTarget(name: "ResolumeTests", dependencies: ["Resolume"]),
    ]
)
