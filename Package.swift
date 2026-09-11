// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scrip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Scrip", targets: ["Scrip"]),
        .library(name: "ScripCore", targets: ["ScripCore"]),
        .library(name: "ScripWeb", targets: ["ScripWeb"]),
    ],
    targets: [
        .target(name: "ScripCore"),
        .target(
            name: "ScripWeb",
            dependencies: ["ScripCore"],
            resources: [.copy("Resources/js")],
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .executableTarget(
            name: "Scrip",
            dependencies: ["ScripCore", "ScripWeb"]
        ),
        .executableTarget(
            name: "ScripCoreCheck",
            dependencies: ["ScripCore"],
            path: "Tests/ScripCoreCheck",
            resources: [.copy("Fixtures")]
        ),
    ]
)
