// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Chio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Chio", targets: ["Chio"]),
        .executable(name: "chio-dashboard", targets: ["ChioDashboard"]),
    ],
    dependencies: [
        // Pin the inspected beta API while the first vertical slice is developed.
        .package(
            url: "https://github.com/SwiftTUI/swift-tui.git",
            revision: "2d84ac7083993da2ef52e9d3d30255467efb9553"
        ),
        // Swift Markdown 0.9.0. A revision pin also permits its conditional
        // Windows build flags without modifying the upstream package.
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            revision: "25cb61d3482054b09ae76ca4f281b1bfe7fe5a43"
        ),
    ],
    targets: [
        .target(
            name: "Chio",
            dependencies: [
                .product(name: "SwiftTUIViews", package: "swift-tui"),
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .executableTarget(
            name: "ChioDashboard",
            dependencies: [
                "Chio",
                .product(name: "SwiftTUI", package: "swift-tui"),
            ],
            path: "Examples/AgentDashboard"
        ),
        .testTarget(
            name: "ChioTests",
            dependencies: [
                "Chio",
                .product(name: "SwiftTUIRuntime", package: "swift-tui"),
            ]
        ),
        .testTarget(
            name: "ChioDashboardTests",
            dependencies: [
                "ChioDashboard",
                .product(name: "SwiftTUIRuntime", package: "swift-tui"),
            ]
        ),
    ]
)
