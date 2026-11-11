// swift-tools-version: 5.9

import PackageDescription
import Foundation

// 本地语音识别引擎（SenseVoice / Whisper，sherpa-onnx）。由 ahakeyconfig-mac/scripts/fetch-sherpa-onnx.sh 生成；
// 未生成时照常编译，只是本地引擎不可用（回退到 Apple Speech）。与 ahakeyconfig-mac/Package.swift 保持一致。
let sherpaOnnxPath = "ahakeyconfig-mac/Vendor/SherpaOnnxC.xcframework"
let hasSherpaOnnx = FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(sherpaOnnxPath).path
)
let sherpaOnnxTargets: [Target] = hasSherpaOnnx
    ? [.binaryTarget(name: "SherpaOnnxC", path: sherpaOnnxPath)]
    : []
let sherpaOnnxDependencies: [Target.Dependency] = hasSherpaOnnx ? ["SherpaOnnxC"] : []

let package = Package(
    name: "AhaKeyConfig",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AhaKeyConfig", targets: ["AhaKeyConfig"]),
        .executable(name: "ahakeyconfig-agent", targets: ["AhaKeyConfigAgent"]),
        .executable(name: "PluginShowcase", targets: ["PluginShowcase"]),
        .library(name: "AhaKeyPluginKit", targets: ["AhaKeyPluginKit"]),
    ],
    dependencies: [
        .package(path: "vibebar"),
    ],
    targets: [
        .target(
            name: "AhaKeyPluginKit",
            path: "ahakeyconfig-mac/Sources/AhaKeyPluginKit"
        ),
        .executableTarget(
            name: "Plugin",
            dependencies: ["AhaKeyPluginKit"],
            path: "ahakeyconfig-mac/Sources/AhaKeyPlugin"
        ),
        .executableTarget(
            name: "PluginShowcase",
            dependencies: ["AhaKeyPluginKit"],
            path: "ahakeyconfig-mac/Sources/AhaKeyPluginShowcase"
        ),
        .executableTarget(
            name: "AhaKeyConfig",
            dependencies: [
                "AhaKeyPluginKit",
                "AhaKeyConfigShared",
                .product(name: "VibeBar", package: "VibeBar"),
            ] + sherpaOnnxDependencies,
            path: "ahakeyconfig-mac/Sources",
            exclude: ["Shared", "Agent", "AhaKeyPlugin", "AhaKeyPluginKit", "AhaKeyPluginShowcase"],
            // 与 scripts/build.sh 中 Info.plist 一致。嵌入 __info_plist 段后 TCC 可识别。
            // Debug 使用单独 plist：系统在「隐私与安全性」列表中显示为「AhaKey Studio（调试）」，与正式包区分。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "ahakeyconfig-mac/Packaging/AhaKeyConfig-EmbeddedInfo-Debug.plist",
                ], .when(platforms: [.macOS], configuration: .debug)),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "ahakeyconfig-mac/Packaging/AhaKeyConfig-EmbeddedInfo.plist",
                ], .when(platforms: [.macOS], configuration: .release)),
            ]
        ),
        .executableTarget(
            name: "AhaKeyConfigAgent",
            dependencies: ["AhaKeyConfigShared"],
            path: "ahakeyconfig-mac/Sources/Agent"
        ),
        .target(name: "AhaKeyConfigShared", path: "ahakeyconfig-mac/Sources/Shared"),
        .testTarget(name: "AhaKeyConfigSharedTests", dependencies: ["AhaKeyConfigShared"], path: "ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests"),
        .testTarget(name: "AhaKeyAgentTests", dependencies: ["AhaKeyConfigAgent", "AhaKeyConfigShared"], path: "ahakeyconfig-mac/Tests/AhaKeyAgentTests"),
        .testTarget(
            name: "AhaKeyConfigTests",
            dependencies: ["AhaKeyConfig"],
            path: "ahakeyconfig-mac/Tests/AhaKeyConfigTests"
        ),
    ] + sherpaOnnxTargets
)
