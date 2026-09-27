// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResoluxPlatformMac",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(name: "ResoluxPlatformMac", targets: ["ResoluxPlatformMac"])
    ],
    dependencies: [
        .package(path: "../ResoluxCore"),
        .package(path: "../ResoluxPlatform"),
    ],
    targets: [
        .target(
            name: "ResoluxPlatformMac",
            dependencies: [
                .product(name: "ResoluxCore", package: "ResoluxCore"),
                .product(name: "ResoluxPlatform", package: "ResoluxPlatform"),
            ]
        ),
    ]
)
