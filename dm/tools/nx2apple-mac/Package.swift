// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NX2AppleContainerTests",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwitchContainerInspector", targets: ["SwitchContainerInspector"])],
    targets: [
        .target(
            name: "SwitchContainerInspector",
            path: "Sources",
            sources: ["SwitchContainerInspector.swift"]
        ),
        .testTarget(
            name: "SwitchContainerInspectorTests",
            dependencies: ["SwitchContainerInspector"],
            path: "Tests"
        )
    ]
)
