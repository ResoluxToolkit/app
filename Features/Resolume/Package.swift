// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Resolume",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Resolume", targets: ["Resolume"]),
        .library(name: "ResolumeUI", targets: ["ResolumeUI"]),
        .executable(name: "ResoluxServer", targets: ["ResoluxServer"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ResoluxCore"),
        .package(path: "../../Packages/ResoluxDesignSystem"),
        .package(
            path: "../../../../../Libraries.dev/packages/border-beam/ports/ios/BorderBeamKit"
        ),
        .package(
            path: "../../../../../Libraries.dev/packages/thinking-orbs/ports/ios/ThinkingOrbsKit"
        ),
        .package(url: "https://github.com/kean/Pulse", from: "5.2.0"),
    ],
    targets: [
        .target(
            name: "Resolume",
            dependencies: [
                .product(name: "ResoluxCore", package: "ResoluxCore"),
                .product(name: "Pulse", package: "Pulse"),
            ],
            resources: [.process("Resources")]),
        .target(name: "ResolumeUI", dependencies: [
            "Resolume",
            .product(name: "ResoluxDesignSystem", package: "ResoluxDesignSystem"),
            .product(name: "BorderBeamKit", package: "BorderBeamKit"),
            .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
        ]),
        .executableTarget(
            name: "ResoluxServer",
            dependencies: ["Resolume"]
        ),
        .testTarget(
            name: "ResolumeTests",
            dependencies: ["Resolume", "ResolumeUI", "ResoluxServer"],
            resources: [.copy("Fixtures/tools-schema.json")]
        ),
    ]
)
