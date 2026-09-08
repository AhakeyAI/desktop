# 参与贡献 AhaKey Desktop

[English](../../CONTRIBUTING.md) · [简体中文](CONTRIBUTING.md)

感谢你帮助改进 AhaKey Desktop！欢迎提交问题反馈、功能建议、文档、翻译和代码贡献。

## 反馈问题或建议功能

- 新建 Issue 前，先搜索[已有问题](https://github.com/AhakeyAI/desktop/issues)。
- 反馈 Bug 时，请提供操作系统、应用版本、相关键盘固件版本、复现步骤、预期行为和实际行为。附上相关日志或截图，并移除凭证及个人信息。
- 建议功能时，请说明希望改善的使用场景。较大的改动建议先通过 Issue 讨论，再开始实现。

## 提交 Pull Request

1. Fork [AhakeyAI/desktop](https://github.com/AhakeyAI/desktop)，克隆自己的 Fork，并为改动创建分支。
2. 阅读[仓库结构](../repo-layout.md)、[架构说明](../architecture.md)和[构建说明](../installation.md)。涉及设备交互时，也请阅读 [BLE 协议](../ble-protocol.md)。
3. 保持改动聚焦，遵循周围代码的风格，并更新相关文档；请同步维护英文 [README.md](../../README.md) 和中文 [docs/zh/README.md](README.md)。
4. 完成下表中的相关检查。涉及硬件或界面时，请说明手动验证内容，并注明无法测试的部分。
5. 向官方仓库发起 [Pull Request](https://github.com/AhakeyAI/desktop/pulls)，说明解决的问题、具体改动、关联 Issue 和验证结果。涉及界面变化时，请附上截图。

只提交源码和必要资源，请勿提交生成的构建产物、安装包、签名证书或凭证。

## 验证改动

使用对应平台和工具链，在下表指定目录执行命令。自动检查配置见 [CI 工作流](../../.github/workflows/ci.yml)。

| 改动范围 | 执行目录 | 检查方式 |
|---|---|---|
| macOS 应用 / 后台 Agent | 仓库根目录 | `swift build`；涉及 macOS 测试覆盖范围的改动时运行 `swift test` |
| TypeScript SDK | `sdks/typescript/` | `npm ci`，然后运行 `npm run typecheck` 和 `npm test` |
| Windows Java 客户端 | `ahakeyconfig-win-java/` | `mvn -q package` |
| Linux Java 客户端 | `ahakeyconfig-ubuntu-java/` | `mvn -q package` |
| 文档 | 修改的文件 | 检查链接、Markdown 展示和中英文一致性 |

其他组件请参考[构建说明](../installation.md)，并在 PR 中说明验证方式。涉及 BLE 或拨杆审批的改动，还需进行真机验证，包括键盘断连、状态无法读取时的行为。
