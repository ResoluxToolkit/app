// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Starter",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "Starter", targets: ["Starter"]),
        .library(name: "StarterUI", targets: ["StarterUI"]),
    ],
    dependencies: [
        .package(
            path: "../../../Libraries.dev/packages/border-beam/ports/ios/BorderBeamKit"
        ),
        .package(path: "../../Packages/ResoluxCore"),
        .package(path: "../../Packages/ResoluxPlatform"),
        .package(path: "../../Packages/ResoluxDesignSystem"),
    ],
    targets: [
        .target(name: "Starter", dependencies: [
            .product(name: "ResoluxCore", package: "ResoluxCore"),
            .product(name: "ResoluxPlatform", package: "ResoluxPlatform"),
        ]),
        .target(name: "StarterUI", dependencies: [
            "Starter",
            .product(name: "BorderBeamKit", package: "BorderBeamKit"),
            .product(name: "ResoluxCore", package: "ResoluxCore"),
            .product(name: "ResoluxDesignSystem", package: "ResoluxDesignSystem"),
        ]),
        .testTarget(name: "StarterTests", dependencies: ["Starter"]),
    ]
)
