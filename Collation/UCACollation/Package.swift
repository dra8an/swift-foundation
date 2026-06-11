// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UCACollation",
    products: [
        .library(name: "UCACollation", targets: ["UCACollation"])
    ],
    targets: [
        .target(
            name: "UCACollation",
            resources: [
                .copy("Resources/ucadata.icu"),
                .copy("Resources/ucadata-icu4x.icu"),
                .copy("Resources/nfd.bin"),
            ]
        ),
        .executableTarget(name: "GenNormData"),
        .testTarget(
            name: "UCACollationTests",
            dependencies: ["UCACollation"],
            resources: [.copy("Golden")]
        ),
    ]
)
