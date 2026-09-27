// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResoluxDesignSystem",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "ResoluxDesignSystem", targets: ["ResoluxDesignSystem"])
    ],
    dependencies: [
        .package(path: "../ResoluxCore")
    ],
    targets: [
        .target(name: "ResoluxDesignSystem", dependencies: [
            .product(name: "ResoluxCore", package: "ResoluxCore")
        ]),
    ]
)
