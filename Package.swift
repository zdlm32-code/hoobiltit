// swift-tools-version: 6.0
import PackageDescription

// Core + sources live in a package so the resolver can be tested on macOS without a
// simulator. The SwiftUI app target consumes RoadSources; nothing here imports MapKit.
let package = Package(
    name: "RoadApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoadCore", targets: ["RoadCore"]),
        .library(name: "RoadSources", targets: ["RoadSources"]),
        .library(name: "RoadUI", targets: ["RoadUI"]),
        .library(name: "RoadStore", targets: ["RoadStore"]),
    ],
    targets: [
        .target(name: "RoadCore", resources: [.process("Resources")]),
        .target(name: "RoadSources", dependencies: ["RoadCore"]),
        .target(name: "RoadStore", dependencies: ["RoadCore"]),
        .target(name: "RoadUI", dependencies: ["RoadCore", "RoadSources", "RoadStore"]),
        // Resolves a pin from the command line, so the pipeline can be exercised against
        // the live services without a simulator.
        .executableTarget(name: "roadlookup", dependencies: ["RoadCore", "RoadSources", "RoadStore"]),
        .testTarget(
            name: "RoadCoreTests",
            dependencies: ["RoadCore", "RoadSources", "RoadStore", "RoadUI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
