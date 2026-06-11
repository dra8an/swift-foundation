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
            resources: [.copy("Resources/ucadata.icu")]
        ),
        .testTarget(
            name: "UCACollationTests",
            dependencies: ["UCACollation"],
            resources: [.copy("Golden")]
        ),
    ]
)
