// swift-tools-version: 5.9

import PackageDescription
let package = Package(
    name: "AhaKeyConfig",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .executable(name: "AhaKeyConfig", targets: ["AhaKeyConfig"]),
        .executable(name: "ahakeyconfig-agent", targets: ["AhaKeyConfigAgent"]),
        .library(name: "AhaKeyConfigShared", targets: ["AhaKeyConfigShared"]),
    ],
    
    targets: [
        .executableTarget(
            name: "AhaKeyConfig",
            dependencies: ["AhaKeyConfigShared"],
            path: "Sources",
            exclude: ["Agent", "Shared", "VirtualDisplayBridge"],
            // 与 scripts/build.sh 中 Info.plist 一致。嵌入 __info_plist 段后 TCC 可识别。
            // Debug 使用单独 plist：系统在「隐私与安全性」列表中显示为「AhaKey Studio（调试）」，与正式包区分。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyConfig-EmbeddedInfo-Debug.plist",
                ], .when(platforms: [.macOS], configuration: .debug)),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyConfig-EmbeddedInfo.plist",
                ], .when(platforms: [.macOS], configuration: .release)),
            ]
        ),
        .executableTarget(
            name: "AhaKeyConfigAgent",
            dependencies: ["AhaKeyConfigShared"],
            path: "Sources/Agent"
        ),
        .target(
            name: "AhaKeyConfigShared",
            dependencies: ["AhaKeyVirtualDisplayBridge"],
            path: "Sources/Shared",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "AhaKeyVirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "AhaKeyConfigSharedTests",
            dependencies: ["AhaKeyConfigShared"],
            path: "Tests/AhaKeyConfigSharedTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AhaKeyConfigProtocolTests",
            dependencies: ["AhaKeyConfig"],
            path: "Tests/AhaKeyConfigProtocolTests"
        ),
    ]
)
