// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PipCore",
    products: [
        .library(name: "PipCore", targets: ["PipCore"]),
    ],
    targets: [
        .target(name: "PipCore"),
        .testTarget(name: "PipCoreTests", dependencies: ["PipCore"]),
    ]
)
