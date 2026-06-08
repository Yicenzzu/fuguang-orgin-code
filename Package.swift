// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Fuguang",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Fuguang", targets: ["Fuguang"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Fuguang"
        )
    ]
)
