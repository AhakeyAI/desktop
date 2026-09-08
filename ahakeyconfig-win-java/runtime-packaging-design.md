# Runtime packaging and locator design

日期：2026-09-08
分支：`windows-flash-rewrite`

## 目标布局

正式安装目录由应用根目录和运行时并列组成：

```text
<application-root>/
  app/ahakey-studio.jar
  firmware/
  wchisp/
    WCHISPTool_CH57x-59x.exe
    WCH55xISPDLL.dll
    CH343PT.DLL
    CH375DLL.DLL (可选的官方组件)
    CONFIG_CH57X59X.WCH
```

`InstalledRuntimeLocator` 从应用根目录解析 `<application-root>/wchisp`，不包含任何
机器特定的 `C:\app`、`C:\aha` 或其他硬编码路径。应用根目录优先取 jpackage launcher
位置；其次从代码源的 `app` 目录和当前工作目录推导。

## 解析优先级

解析顺序固定为：

1. 安装目录 `<application-root>/wchisp`；
2. JVM 参数 `-Dahakey.wchisp.path=<path>`；
3. 环境变量 `AHAKEY_WCHISP_PATH=<path>`；
4. 既有开发环境候选（当前工作目录向上搜索 `tools/wchisp`、`wchisp` 和
   `WCHISPTool_CH57x-59x`）。

安装目录使用现有 `WchIspRuntimeContract` 的正式校验。显式 JVM/环境路径继续使用
`WchIspRuntimeProvider.resolve(Path)` 的开发准入策略，因此缺少 metadata 时仍会返回
`RuntimeIdentity.UNKNOWN`，但四个必需文件缺一不可。显式路径无效时返回包含实际路径的
明确错误；不会静默增加任何 `C:\app` fallback。

## 调用边界

`DefaultOfficialWchIspAdapter` 只依赖 `RuntimeLocator`、presence probe 和通用
`WchIspRunner`。检测是用户触发的一次性 ISP presence 检查，不建立 USB 后台监听，也不
运行 `-u get`。烧录仍由官方工具执行 `-o download -f <hex>`；运行时诊断、操作日志和
`FirmwarePostVerifier` 保持在 `FirmwareUpdateService`。

`RuntimeProvider` 现在是兼容旧测试 seam 的 `RuntimeLocator` 子接口。旧 workspace、
CONFIG patch 和 UID parser 类没有删除，但不在 Studio 公开生产构造器的调用链中使用。

## 自动验证

`InstalledRuntimeLocatorTest` 覆盖安装目录解析、JVM 显式路径、环境变量路径和缺失运行时
的错误证据；`OfficialWchIspAdapterTest` 验证适配器仍不发送 `-u get`，下载命令仍为
`-o download -f`。本轮完整 Maven 测试结果和 package 产物检查以命令实际输出为准。

## 尚未验证

本轮未启动 Studio，未运行 WCHISP，未执行真实 ISP/烧录或 post-verify。正式安装包的
`<application-root>/wchisp` 复制、签名安装包和 WiX 仍需在发布环境验证；真实 runtime
metadata/config contract 与硬件行为不能由单元测试替代。
