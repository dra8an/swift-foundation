// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Collation",
    products: [
        .library(name: "Collation", targets: ["Collation"])
    ],
    targets: [
        .target(
            name: "Collation",
            resources: [
                .copy("Resources/ucadata.icu"),
                .copy("Resources/ucadata-icu4x.icu"),
                .copy("Resources/nfd.bin"),
                .copy("Resources/tailorings"),
            ]
        ),
        .executableTarget(name: "GenNormData"),
        .executableTarget(name: "Bench", dependencies: ["Collation"]),
        .testTarget(
            name: "CollationTests",
            dependencies: ["Collation"],
            resources: [.copy("Golden"), .copy("Conformance")]
        ),
    ]
)
