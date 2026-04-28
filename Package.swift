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
            exclude: ["Agent"],
            // 与 scripts/build.sh 中 Info.plist 的隐私说明一致。Xcode 直接 Run 时 bundle 内
            // 常没有完整 plist，导致麦克风/语音识别权限弹窗不出现；嵌入 __info_plist 段后 TCC 可识别。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyConfig-EmbeddedInfo.plist",
                ], .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "AhaKeyConfigAgent",
            path: "Sources/Agent"
        ),
    ]
)
