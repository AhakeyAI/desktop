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
        .library(name: "RuntimeXPCServer", targets: ["RuntimeXPCServer"]),
        .executable(name: "RuntimeXPCSmokeServer", targets: ["RuntimeXPCSmokeServer"]),
        .executable(name: "RuntimeXPCSmokeClient", targets: ["RuntimeXPCSmokeClient"]),
    ],
    
    targets: [
        .executableTarget(
            name: "AhaKeyConfig",
            dependencies: ["AhaKeyConfigShared"],
            path: "Sources",
            exclude: ["Agent", "Shared", "VirtualDisplayBridge", "RuntimeXPCServer"],
            // 与 scripts/build.sh 中 Info.plist 一致。嵌入 __info_plist 段后 TCC 可识别。
            // Debug 使用单独 plist：系统在「隐私与安全性」列表中显示为「AhaKey Studio（调试）」，与正式包区分。
            linkerSettings: [
                .linkedFramework("IOKit"),
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
            dependencies: ["AhaKeyConfigShared", "RuntimeXPCServer"],
            path: "Sources/Agent"
        ),
        .target(
            name: "AhaKeyConfigShared",
            dependencies: ["AhaKeyVirtualDisplayBridge"],
            path: "Sources/Shared",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "AhaKeyVirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        // WBS 5.2：最小 C libxpc bridge（含 peer code signing requirement 包装）。
        .target(
            name: "CLibXPC",
            path: "Sources/RuntimeXPCServer/CLibXPC",
            publicHeadersPath: "include"
        ),
        // WBS 5.2：生产 libxpc listener/accepted-peer 边界（macOS 12+）。
        .target(
            name: "RuntimeXPCServer",
            dependencies: ["CLibXPC", "AhaKeyConfigShared"],
            path: "Sources/RuntimeXPCServer/RuntimeXPCServer"
        ),
        // WBS 5.2 smoke：真实双进程签名验证用 server/client helper（仅测试用途）。
        .executableTarget(
            name: "RuntimeXPCSmokeServer",
            dependencies: ["RuntimeXPCServer", "AhaKeyConfigShared"],
            path: "Sources/RuntimeXPCServer/SmokeServer"
        ),
        .executableTarget(
            name: "RuntimeXPCSmokeClient",
            dependencies: ["CLibXPC", "AhaKeyConfigShared"],
            path: "Sources/RuntimeXPCServer/SmokeClient"
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
        .testTarget(
            name: "RuntimeXPCServerTests",
            dependencies: ["RuntimeXPCServer", "AhaKeyConfigShared"]
        ),
        .testTarget(
            name: "AhaKeyAgentTests",
            dependencies: ["AhaKeyConfigAgent", "AhaKeyConfigShared"],
            path: "Tests/AhaKeyAgentTests"
        ),
    ]
)
