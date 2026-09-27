// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResoluxCore",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "ResoluxCore", targets: ["ResoluxCore"])
    ],
    targets: [
        .target(name: "ResoluxCore"),
        .testTarget(name: "ResoluxCoreTests", dependencies: ["ResoluxCore"]),
    ]
)
