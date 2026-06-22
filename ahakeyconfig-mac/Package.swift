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
        .executable(name: "PluginShowcase", targets: ["PluginShowcase"]),
        .library(name: "AhaKeyPluginKit", targets: ["AhaKeyPluginKit"]),
    ],

    targets: [
        .target(
            name: "AhaKeyPluginKit",
            path: "Sources/AhaKeyPluginKit"
        ),
        .executableTarget(
            name: "Plugin",
            dependencies: ["AhaKeyPluginKit"],
            path: "Sources/AhaKeyPlugin"
        ),
        .executableTarget(
            name: "PluginShowcase",
            dependencies: ["AhaKeyPluginKit"],
            path: "Sources/AhaKeyPluginShowcase"
        ),
        .executableTarget(
            name: "AhaKeyConfig",
            dependencies: ["AhaKeyPluginKit"],
            path: "Sources",
            exclude: ["Agent", "AhaKeyPlugin", "AhaKeyPluginKit", "AhaKeyPluginShowcase"],
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
            path: "Sources/Agent"
        ),
    ]
)
