// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResoluxPlatform",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "ResoluxPlatform", targets: ["ResoluxPlatform"])
    ],
    dependencies: [
        .package(path: "../ResoluxCore")
    ],
    targets: [
        .target(name: "ResoluxPlatform", dependencies: [
            .product(name: "ResoluxCore", package: "ResoluxCore")
        ]),
        .testTarget(name: "ResoluxPlatformTests", dependencies: ["ResoluxPlatform"]),
    ]
)
