# Official WCHISP Adapter migration review

日期：2026-09-08
分支：`windows-flash-rewrite`

## 结果摘要

生产调用链已迁移为：

```text
FirmwareUpdateService
        |
OfficialWchIspAdapter
        |
WCHISPTool_CH57x-59x.exe
```

Studio 仍拥有用户流程、`PREFLIGHT -> WAITING_ISP -> DETECTING -> READY ->
FLASHING -> WAITING_RECONNECT -> VERIFYING -> SUCCESS` 状态机、HEX 校验、诊断日志和
`FirmwarePostVerifier`。官方工具拥有 ISP 通信、芯片识别和下载实现。

## 迁移内容

- 新增 `OfficialWchIspAdapter` 接口及 `DefaultOfficialWchIspAdapter` 实现。
- `detectDevice()` 只执行一次 runtime 解析和 ISP presence 检查；UID 为空是合法结果，
  不启动 `-u get`，不建立 USB 后台监听。
- `flashFirmware(Path)` 直接执行官方 `-o download -f <hex>`，不复制 workspace、
  不 patch CONFIG、不使用 UID parser；原始进程证据交给服务写入诊断目录。
- `FirmwareUpdateService(BleManager)` 和 Studio 生产构造器改走 adapter。旧 workspace/
  config/parser 代码保留在 package-private 测试兼容路径，未删除、未用于生产调用链。
- `DiagnosticResult.ready()` 新增 `officialAdapterReady`，生产 readiness 不再依赖 UID 或
  自研 `ChipMatched` gate；UID 只作为可选显示信息。
- overlay source/allowlist、独立 release artifact test 已加入两个 adapter 类；
  `firmware-capabilities.properties` 的既有打包规则保持不变。

## 测试

`OfficialWchIspAdapterTest` 覆盖：

1. 检测只做 presence check，runner 不被调用，明确不发送 `-u get`；
2. 下载命令严格为 `-o download -f <hex>`，不含 `-c` 或 `-u`；
3. FirmwareUpdateService 通过 adapter 走完整状态链，UID 为空仍不阻断烧录。

既有 firmware、BLE、Hook、GIF/OLED 和生命周期测试保持兼容。本轮 `mvn clean test` 与
`mvn clean package` 均为 221 tests / 0 failures / 0 errors / 0 skipped；独立
`Test-ReleaseArtifactContents.ps1` 返回 `RELEASE_ARTIFACT_CONTENTS=OK`。真机 WCHISP
下载、设备重连回读、签名安装包和正式 overlay 尚未在本轮执行。

## 风险与后续验证

- `DefaultOfficialWchIspAdapter` 使用官方工具 exit code 作为下载阶段成功信号，最终结果
  必须由 `FirmwarePostVerifier` 设备回读确认；不能仅凭 exit code 宣称固件已验证。
- 官方 GUI 的 UID/BTVER 控制模式仍属于 vendor-owned 能力；本迁移不猜测窗口消息或
  DLL callback，UID 保持 optional。
- 当前工作区没有外层稳定化计划文件和可用正式安装基线；release overlay、WiX、真实
  CH582 ISP 和 post verify 需在相应环境中单独验证。
