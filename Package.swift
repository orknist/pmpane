// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PMPaneCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PMPaneCore", targets: ["PMPaneCore"]),
    ],
    targets: [
        .target(
            name: "PMPaneCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PMPaneCoreTests",
            dependencies: ["PMPaneCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
