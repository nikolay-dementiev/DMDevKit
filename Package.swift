// swift-tools-version: 6.0
// 6.0 is the floor of the libraries that use DMDevKit through their nested Tools/Package.swift.

import PackageDescription

let package = Package(
    name: "DMDevKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "devkit", targets: ["devkit"]),
    ],
    targets: [
        // The dispatcher logic. It is not a product: only the executable is the interface.
        .target(name: "DevKitCore"),
        // The composition root. It owns the scripts as resources, so Bundle.module stays here.
        .executableTarget(
            name: "devkit",
            dependencies: ["DevKitCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "DevKitTests",
            dependencies: ["DevKitCore", "devkit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
