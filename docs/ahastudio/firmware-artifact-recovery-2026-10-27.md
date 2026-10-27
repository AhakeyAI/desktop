# 新固件精确产物恢复记录 — 2026-10-27

已恢复 Harness 指定组合 HEX，完整 SHA256 与原机器门禁记录一致。此前要求用户提供路径的依赖关闭；不是换用另一份固件，也不是重新批准一份不同字节的候选。未刷写键盘、未执行整机恢复。

## 固定输入与产物

- 源码：`292a49f32939e2b778b15eceb194746133d3b2c7`。
- 最新分支：`harness/x1-refactor-main@0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb`；与上述候选的 `APP`、`Profile` 和生产构建脚本无差异。
- 本机 HEX：`/Users/heartline/Documents/Codex/local-builds/firmware-ws45-292a49f-20261027/HID_Keyboard_582m_vibe_coding.hex`。
- SHA256：`6EC0413CFC983788CDC99F628F0F8E2A64C6AF147D2A5E1727A03F036BF1123C`。
- 同目录保存源码归档、ELF/BIN/MAP、完整构建命令与日志、原 gate receipt、SDK校验、Mac host检查及可传入路径的重建脚本。
- 版本追溯回执：[firmware-artifact-recovery-2026-10-27.json](../validation/connect-talk-hil-2026-10-22/firmware-artifact-recovery-2026-10-27.json)。

## 历史刷写对账

10月13日 CP4D 的 HEX 已在 `local-builds/firmware-ws2-cp4d-20261013` 找到，SHA256 为 `6f9759eb912ec067564c4e63558589ab9732126344d52c2d2a278383119516be`；10月19日刷入的是 `ws3-memory-fix.hex`，SHA256 为 `ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539`，刷写日志记录 Verify OK。两次实际用包均由归档恢复下载，不是本次 WS45 包。

扩大搜索检查了329份可读HEX、143个不同原始哈希，含LF/CRLF和末尾换行变体，没有现成目标。Downloads受macOS隐私权限限制，未称全机穷尽搜索；没有修改系统权限或读取私有设备配置备份。

## 恢复构建链路

旧工作目录存在CH583 SDK，原manifest与24项consumed set校验通过。旧xPack13.2不支持 `WCH-Interrupt-fast`，不通过改成INT_SOFT或忽略属性来凑构建。

从[官方MounRiver下载页](https://www.mounriver.com/download/)的公开下载接口取得 `MRS_Toolchain_MAC_V240.zip`，1,014,339,257字节，SHA256 `c0a0c9cf9661e835c52b9170f08a1b45a97b076eb2947fe76006016699ffdad1`。包内保留的 `Toolchain/RISC-V Embedded GCC` 是 `riscv-none-embed-gcc 8.2.0 x86_64`，快中断最小编译检查通过。工具链保存在 `local-builds/toolchains/mrs-mac-v240`，不污染固件工作树。

将原PowerShell脚本的77个C源、排序、编译和链接参数等价转成Mac命令，`SOURCE_DATE_EPOCH=0`；不改生产源码、启动代码、中断ABI或SDK。生成的HEX完整哈希恰好与原Windows1.92门禁记录一致。发布日志记录FLASH 269,756字节、RAM 29,124字节；这些不是新增预算批准。

## 证据边界与后续

原13项机器检查PASS来自既有 `20261025T133952/gate-receipt.json`，不是本轮重跑。Mac额外编译执行了现有route-store及Restore状态两组host测试，均通过；不将其称为完整13项重验。恢复的字节和门禁绑定对象相同，未改源码、契约、STATE或锁，不把重建宣称新候选审批/Owner UAT通过。

下一步以build512与本HEX固定组合做只读/兼容准备，最后集中安排ISP刷写、逐模式Consumer往返、连接保持与必要实体动作。整机恢复会重置配置，须另按具体范围确认，不能与刷机顺带执行。Issue #9可重复整机恢复、长宏、独立短长按、正式目录/恢复镜像和完整矩阵不因找回HEX而自动完成。

客户端现有 `FirmwareImageValidator` 已直接校验恢复包及两份历史HEX：三者记录校验和、EOF和CH582 CodeFlash范围均通过；本包758,812字节、哈希再次一致。内置arm64烧录工具可正常显示命令帮助。旧包可解析不代表跨版本配置回退已通过；未对设备执行probe/reset/erase/flash。
