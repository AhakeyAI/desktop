// swift-tools-version: 5.9

import PackageDescription
let package = Package(
    name: "AhaKeyConfig",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "AhaKeyConfig", targets: ["AhaKeyConfig"]),
        .executable(name: "ahakeyconfig-agent", targets: ["AhaKeyConfigAgent"]),
    ],
    targets: [
        .executableTarget(
            name: "AhaKeyConfig",
            path: "Sources",
            exclude: ["Agent"]
        ),
        .executableTarget(
            name: "AhaKeyConfigAgent",
            path: "Sources/Agent"
        ),
    ]
)
