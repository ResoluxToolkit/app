// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResoluxPlatformiOS",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(name: "ResoluxPlatformiOS", targets: ["ResoluxPlatformiOS"])
    ],
    dependencies: [
        .package(path: "../ResoluxCore"),
        .package(path: "../ResoluxPlatform"),
    ],
    targets: [
        .target(
            name: "ResoluxPlatformiOS",
            dependencies: [
                .product(name: "ResoluxCore", package: "ResoluxCore"),
                .product(name: "ResoluxPlatform", package: "ResoluxPlatform"),
            ]
        ),
    ]
)
