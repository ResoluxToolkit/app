// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Resolume",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Resolume", targets: ["Resolume"]),
        .library(name: "ResolumeUI", targets: ["ResolumeUI"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ResoluxCore"),
        .package(path: "../../Packages/ResoluxDesignSystem"),
    ],
    targets: [
        .target(name: "Resolume", dependencies: [.product(name: "ResoluxCore", package: "ResoluxCore")]),
        .target(name: "ResolumeUI", dependencies: [
            "Resolume",
            .product(name: "ResoluxDesignSystem", package: "ResoluxDesignSystem"),
        ]),
        .testTarget(
            name: "ResolumeTests",
            dependencies: ["Resolume", "ResolumeUI"],
            resources: [.copy("Fixtures/tools-schema.json")]
        ),
    ]
)
