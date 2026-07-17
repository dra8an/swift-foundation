// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "duffett-smith-port",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/Users/draganbesevic/Projects/claude/CalendarAPI/icu4swift")
    ],
    targets: [
        .executableTarget(
            name: "dsverify",
            dependencies: [
                .product(name: "CalendarCore", package: "icu4swift"),
                .product(name: "CalendarSimple", package: "icu4swift"),
                .product(name: "AstronomicalEngine", package: "icu4swift"),
            ]
        )
    ]
)
