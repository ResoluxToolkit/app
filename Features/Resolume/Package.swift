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
        .package(
            path: "../../../Libraries.dev/packages/border-beam/ports/ios/BorderBeamKit"
        ),
    ],
    targets: [
        .target(name: "Resolume", dependencies: [.product(name: "ResoluxCore", package: "ResoluxCore")]),
        .target(name: "ResolumeUI", dependencies: [
            "Resolume",
            .product(name: "ResoluxDesignSystem", package: "ResoluxDesignSystem"),
            .product(name: "BorderBeamKit", package: "BorderBeamKit"),
        ]),
        .testTarget(
            name: "ResolumeTests",
            dependencies: ["Resolume", "ResolumeUI"],
            resources: [.copy("Fixtures/tools-schema.json")]
        ),
    ]
)
