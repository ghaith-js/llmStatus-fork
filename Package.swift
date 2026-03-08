// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LLMStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LLMStatus",
            path: "LLMStatus",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LLMStatusTests",
            dependencies: ["LLMStatus"],
            path: "LLMStatusTests"
        ),
    ]
)
