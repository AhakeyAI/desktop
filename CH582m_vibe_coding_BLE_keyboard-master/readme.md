<a id="top"></a>

<p align="center">
  <a href="#zh-cn"><strong>简体中文</strong></a> ·
  <a href="#en"><strong>English</strong></a>
</p>

---

<a id="zh-cn"></a>

<h1 align="center">⌨️ AhaKey X1 Hardware Source</h1>

<p align="center">
  <strong>AhaKey X1 官方硬件 / 固件基线源码仓库</strong>
</p>

<p align="center">
  官方固件基线 · 硬件参考资料 · 本地调试 · 受控共创
</p>

<p align="center">
  <img alt="status" src="https://img.shields.io/badge/status-private%20access-orange">
  <img alt="source" src="https://img.shields.io/badge/source-controlled-red">
  <img alt="hardware" src="https://img.shields.io/badge/hardware-AhaKey%20X1-blue">
  <img alt="firmware" src="https://img.shields.io/badge/firmware-CH582M%2FCH58x-green">
</p>

---

## 仓库说明

本仓库包含 AhaKey X1 / Vibe Coding Keyboard 相关的**官方硬件与固件基线源码资料**，包括固件工程、部分硬件参考资料、编译说明、烧录说明和调试参考。

本仓库**不是公开开源仓库**，而是 AhaKey Hardware Source Access Program 的受控访问仓库。访问本仓库的目的，是支持真实的学习、调试、研究、教程共创、固件级问题排查和社区协作。

请注意：

- 本仓库默认分支用于维护 AhaKey X1 官方硬件对应的固件基线；
- 默认分支不代表所有用户实验版本、个性化版本或自定义固件版本；
- Release 仅用于发布 AhaKey 官方确认过的固件、hex、烧录说明和版本资料；
- 用户自定义固件、实验性 hex、未测试版本不会作为官方 Release 发布。

AhaKey 采用分层开放机制：

- 官方桌面客户端：开源维护
- BLE 协议文档：公开维护
- 客户端示例 / SDK / workflow：逐步开放
- 社区项目与二创：鼓励展示和共创
- 固件源码、硬件设计文件、PCB、BOM、生产资料：不默认公开，通过受控访问计划提供

大多数 AhaKey 客户端、脚本、工具和 AI workflow 开发并不需要访问本仓库。请优先查看：

- AhaKey Protocol: https://github.com/AhakeyAI/protocol
- AhaKey Desktop: https://github.com/AhakeyAI/desktop
- Community Projects: https://github.com/AhakeyAI/awesome-ahakey

---

## 访问边界

获得本仓库访问权限后，你可以：

- 阅读和学习源码
- clone 到本地查看、编译和调试
- 为学习、测试、研究进行本地修改
- 研究固件行为和硬件交互
- 反馈问题、提交建议或贡献修复
- 基于官方基线进行本地实验和验证

未经 AhaKey 书面授权，你不得：

- 公开上传、网络分发、转发、出售或共享本仓库内容
- 将本仓库或衍生源码公开发布到 GitHub、Gitee、GitLab、论坛、网盘或其他公开平台
- 使用相关资料自行打板、仿制、量产、销售或开发竞争性硬件产品
- 删除 AhaKey 的版权、署名、来源说明或标识
- 冒充 AhaKey 官方固件、硬件、发布版本、网站或维护者
- 将修改版固件作为 AhaKey 官方版本对外发布

> 自定义固件仅用于个人测试、研究和调试。  
> AhaKey 仅对官方发布版本提供稳定支持。

---

## 官方基线与社区贡献

本仓库是 **AhaKey X1 官方硬件 / 固件基线源码仓库**，不是社区自定义固件合集。

如果你只是想理解官方出厂版本、查看源码、编译固件、进行本地调试，请以本仓库为准。

如果你希望反馈修改、提交 patch、分享实验性固件思路、提出硬件 proposal，建议提交到用户贡献仓库：

[AhaKey-X1-hardware-contributions](https://github.com/AhakeyAI/AhaKey-X1-hardware-contributions)

AhaKey 团队会定期 review 贡献仓库中的反馈和改动。适合进入官方版本的内容，会由维护者整理、测试后再合入本仓库。

### 我的贡献应该放在哪里？

| 贡献类型 | 推荐位置 | 是否进入官方基线 |
|---|---|---|
| 固件 bug 修复 | 用户贡献仓库 / patch / 私下提交 | 可评估进入 |
| 编译、烧录、调试文档补充 | 用户贡献仓库 | 可评估进入 |
| 稳定性、兼容性、功耗优化 | 先提交 proposal，再评估 | 可评估进入 |
| 改变默认交互逻辑的个人实验版本 | 用户贡献仓库的 experiments / proposal | 不默认进入 |
| 用户自行编译的 hex | 本地测试使用 | 不进入官方 Release |
| 外壳、键帽、支架、桌面 setup | awesome-ahakey / Discussion | 不进入本仓库 |
| 第三方客户端、脚本、workflow | protocol / awesome-ahakey | 不进入本仓库 |
| PCB layout、BOM、Gerber、生产测试资料 | 联系 AhaKey 企业微信专人客服进一步沟通 | 不默认提供 |

### Release 说明

本仓库的 Release 仅用于发布：

- AhaKey 官方确认过的固件版本
- 官方出厂 hex
- 官方烧录说明
- 官方测试通过的版本资料
- 官方图文说明和下载说明

Release 不用于发布：

- 用户自定义固件
- 用户实验性 hex
- 未经测试的功能分支
- 个人 workflow 版本
- 未经 AhaKey 团队确认的第三方固件包

---

## 硬件资料边界

当前仓库主要包含：

- 官方固件源码
- 编译 / 烧录说明
- 调试参考资料
- 部分硬件参考资料
- 原理图或相关说明

以下资料不默认通过仓库提供：

- PCB layout
- Gerber
- BOM
- 生产测试资料
- 供应链资料
- 结构量产文件
- 其他可用于复刻、打板、量产或商业销售的资料

如果你的研究、调试或共创确实需要更完整的硬件资料，请联系 AhaKey 企业微信专人客服进一步沟通。相关资料会根据用途、风险和合作方式单独评估。

---

## 硬件功能概览

AhaKey X1 / Vibe Coding Keyboard 是一个面向 AI 编程工作流的物理控制键盘，早期版本围绕 Claude Code 等 AI coding 场景设计。

主要能力包括：

- **四个实体按键**
  - 批准 / Yes
  - 拒绝 / No
  - 语音输入 / Voice input
  - 自定义按键 / Custom key

- **拨杆切换**
  - 手动审批模式
  - 自动批准模式

- **双模连接**
  - Type-C
  - Bluetooth / BLE

- **OLED 显示**
  - 当前状态
  - 像素图
  - 自定义图片或动图

- **RGB 状态反馈**
  - 空闲
  - 工作中
  - 等待审批
  - 自动模式
  - 语音输入
  - 其他自定义状态

- **AI 编程工作流联动**
  - Claude / Cursor / Codex 等 Agent 工作流状态
  - 审批按钮
  - 语音转 prompt
  - 状态显示与反馈

---

## 系统工作流

当前硬件 / 固件相关链路大致如下：

```text
AhaKey Keyboard Device
→ BLE / HID
→ Computer
→ Bridge / Driver / Host Tool
→ AI Coding Tool / Agent Workflow
```

早期工程中，整体链路包含：

```text
键盘设备
→ BLE / HID
→ 电脑
→ BLE bridge / TCP interface
→ Host software / config tool
→ Claude hook / agent status reporter
```

其中：

- 本仓库主要包含键盘设备侧固件与硬件相关资料
- 桌面端、配置工具、hook、workflow 等内容会逐步迁移到公开或独立仓库
- 公开协议和第三方客户端开发请优先查看 `AhakeyAI/protocol`

---

## 编译环境

早期固件工程使用：

- 编译软件：`MounRiver Studio`
- 下载软件：`WCHISP Studio`
- 芯片 / SDK：WCH CH58x 系列相关 SDK

参考 SDK：

```text
https://www.wch.cn/downloads/CH583EVT_ZIP.html
```

---

## 如何构建固件

参考流程：

```text
1. 下载 WCH 官方 SDK
2. 将本仓库中的工程代码放入 SDK 示例目录，例如 EXAM/BLE
3. 打开工程文件 HID_Keyboard_582m_vibe_coding.wvproj
4. 使用 MounRiver Studio 编译
5. 编译结果通常位于 obj/ 目录
```

示例输出文件：

```text
obj/HID_Keyboard_582m_vibe_coding.hex
```

不同版本的 SDK、工程路径和芯片型号可能存在差异，请以当前仓库内实际工程文件为准。

---

## 如何下载 / 烧录

参考流程：

```text
1. 安装 WCHISP Studio
2. 让芯片进入 boot mode
3. 通过 USB 下载固件
4. 烧录后进行基础按键、BLE、OLED、RGB、拨杆等功能测试
```

更详细的下载、烧录和图文说明，请查看：

[Release v1.0 下载与烧录说明](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/releases/tag/v1.0)

注意：

- boot 引脚和烧录方式可能因硬件版本不同而不同
- 刷写自定义固件可能导致设备行为异常
- 请在理解风险后再进行测试
- 不建议将未经确认的修改版固件提供给普通用户使用

---

## 反馈与贡献

如果你希望把修改、实验或建议反馈给 AhaKey，请优先使用用户贡献仓库：

[AhaKey-X1-hardware-contributions](https://github.com/AhakeyAI/AhaKey-X1-hardware-contributions)

推荐流程：

```text
查看本仓库官方基线
→ clone 到本地
→ 本地修改、编译、测试
→ 判断改动类型
→ 在贡献仓库中新建分支
→ 将 proposal / patch / experiment / docs 提交到新分支
→ 提交 Pull Request，或将分支链接发给 AhaKey 团队
→ AhaKey 团队 review
→ 适合官方化的改动由维护者整理后进入官方基线
→ 官方测试通过后进入 Release
```

**请务必新建分支提交，不要直接提交到 `main` / `master` 分支。**

这样可以：

- 清晰保留贡献者的 GitHub 身份和提交记录
- 方便 AhaKey 团队 review、讨论和回溯
- 避免个人实验内容影响官方基线或贡献仓库主分支
- 让后续 Release notes 能更准确地鸣谢贡献者

推荐分支命名：

```text
fix/<github-id>-short-description
docs/<github-id>-short-description
experiment/<github-id>-short-description
proposal/<github-id>-short-description
```

一个好的贡献说明应包含：

- 改了什么
- 为什么需要这个修改
- 是否改变默认交互逻辑
- 如何测试
- 影响的设备版本或固件版本
- 必要时提供日志、截图、串口输出或测试记录

不是所有实验性修改都会合并进官方固件。部分想法可能更适合作为本地实验、社区记录或后续版本候选功能保留。

---

## 联系方式

如有仓库、访问权限、烧录调试、硬件资料或协作相关问题，可以联系 AhaKey 团队。

<p align="center">
  <img src="https://github.com/AhakeyAI/.github/blob/main/profile/assets/qr/wecom-support.png?raw=true" width="180" alt="AhaKey WeCom Support QR Code">
</p>

<p align="center">
  企业微信专人客服
</p>

也可以通过邮箱联系：

```text
zhangxinyang@ahakey.cn
```

<p align="right"><a href="#top">↑ Back to top</a></p>

---

<a id="en"></a>

<h1 align="center">⌨️ AhaKey X1 Hardware Source</h1>

<p align="center">
  <strong>Official hardware and firmware baseline source repository for AhaKey X1</strong>
</p>

<p align="center">
  Official Firmware Baseline · Hardware References · Local Debugging · Controlled Collaboration
</p>

<p align="center">
  <img alt="status" src="https://img.shields.io/badge/status-private%20access-orange">
  <img alt="source" src="https://img.shields.io/badge/source-controlled-red">
  <img alt="hardware" src="https://img.shields.io/badge/hardware-AhaKey%20X1-blue">
  <img alt="firmware" src="https://img.shields.io/badge/firmware-CH582M%2FCH58x-green">
</p>

---

## Repository overview

This repository contains the official hardware and firmware baseline source materials for AhaKey X1 / Vibe Coding Keyboard, including firmware projects, selected hardware references, build notes, flashing notes, and debugging references.

This is **not a public open-source repository**. Access is provided through the AhaKey Hardware Source Access Program for real learning, debugging, research, tutorial co-creation, firmware-level troubleshooting, and approved community collaboration.

Please note:

- The default branch is used to maintain the official firmware baseline for AhaKey X1 hardware.
- The default branch does not represent all user experiments, personalized versions, or custom firmware versions.
- Releases are only for AhaKey-reviewed official firmware, hex files, flashing guides, and version materials.
- User-customized firmware, experimental hex files, and untested versions will not be published as official Releases.

AhaKey follows a layered openness model:

- Official desktop client: open source
- BLE protocol documentation: public
- Client examples / SDK / workflows: gradually opened
- Community projects and remixes: encouraged
- Firmware source, hardware design files, PCB, BOM, and production materials: not public by default, provided through controlled access

Most AhaKey client, script, tool, and AI workflow development does **not** require access to this repository. Please start with:

- AhaKey Protocol: https://github.com/AhakeyAI/protocol
- AhaKey Desktop: https://github.com/AhakeyAI/desktop
- Community Projects: https://github.com/AhakeyAI/awesome-ahakey

---

## Access boundaries

With approved access, you may:

- read and study the source code
- clone this repository to your local machine
- make local modifications for learning, testing, or debugging
- investigate firmware behavior and hardware interactions
- report issues, suggest improvements, or contribute fixes
- run local experiments based on the official baseline

Without written authorization from AhaKey, you may not:

- publicly upload, redistribute, forward, sell, or share controlled materials
- publish this repository or derived source code to public GitHub, Gitee, GitLab, forums, cloud drives, or other public platforms
- use these materials for board reproduction, cloning, manufacturing, resale, or competing hardware development
- remove AhaKey copyright, attribution, source notices, or identifiers
- impersonate official AhaKey firmware, hardware, releases, websites, or maintainers
- distribute modified firmware as an official AhaKey release

> Custom firmware is for personal testing, research, and debugging only.  
> AhaKey only provides stable support for official firmware releases.

---

## Official baseline and community contributions

This repository is the **official hardware / firmware baseline source repository** for AhaKey X1. It is not a collection of community-customized firmware.

If you want to understand the official factory version, read the source code, build firmware, or debug locally, use this repository as the baseline.

If you want to submit patches, share experimental firmware ideas, propose hardware changes, or contribute documentation, please use the contribution repository:

[AhaKey-X1-hardware-contributions](https://github.com/AhakeyAI/AhaKey-X1-hardware-contributions)

The AhaKey team will regularly review feedback and changes from the contribution repository. Suitable changes may be cleaned up, tested, and merged into this official baseline repository by maintainers.

### Where should my contribution go?

| Contribution type | Recommended place | Can it enter official baseline? |
|---|---|---|
| Firmware bug fix | Contribution repo / patch / private submission | May be evaluated |
| Build, flashing, or debugging docs | Contribution repo | May be evaluated |
| Stability, compatibility, or power optimization | Proposal first, then evaluation | May be evaluated |
| Personal experimental version changing default behavior | experiments / proposal in contribution repo | Not by default |
| User-built hex files | Local testing only | Not released officially |
| Cases, keycaps, stands, desk setup | awesome-ahakey / Discussion | Not in this repo |
| Third-party clients, scripts, workflows | protocol / awesome-ahakey | Not in this repo |
| PCB layout, BOM, Gerber, production test materials | Contact AhaKey WeCom support for further discussion | Not provided by default |

### Release policy

This repository’s Releases are only for:

- AhaKey-reviewed official firmware versions
- official factory hex files
- official flashing guides
- officially tested version materials
- official visual download / flashing instructions

Releases are not for:

- user-customized firmware
- user experimental hex files
- untested feature branches
- personal workflow versions
- third-party firmware packages not reviewed by AhaKey

---

## Hardware materials boundary

This repository currently mainly includes:

- official firmware source code
- build / flashing notes
- debugging references
- selected hardware reference materials
- schematics or related notes

The following materials are not provided through this repository by default:

- PCB layout
- Gerber
- BOM
- production test materials
- supply-chain information
- mechanical production files
- other files that can be used for reproduction, board manufacturing, mass production, or commercial resale

If your research, debugging, or collaboration truly requires more complete hardware materials, please contact AhaKey WeCom support for further discussion. These materials will be evaluated separately based on purpose, risk, and collaboration scope.

---

## Hardware features

AhaKey X1 / Vibe Coding Keyboard is a physical control keyboard designed for AI coding workflows, originally built around Claude Code and similar AI coding tools.

Main capabilities include:

- **Four physical keys**
  - Approve / Yes
  - Reject / No
  - Voice input
  - Custom key

- **Toggle switch**
  - Manual approval mode
  - Auto-approval mode

- **Dual-mode connection**
  - Type-C
  - Bluetooth / BLE

- **OLED display**
  - Current status
  - Pixel art
  - Custom images or animations

- **RGB status feedback**
  - Idle
  - Working
  - Waiting for approval
  - Auto mode
  - Voice input
  - Other custom states

- **AI coding workflow integration**
  - Claude / Cursor / Codex agent status
  - Approval button
  - Voice-to-prompt
  - Status display and feedback

---

## System workflow

The hardware / firmware workflow is roughly:

```text
AhaKey Keyboard Device
→ BLE / HID
→ Computer
→ Bridge / Driver / Host Tool
→ AI Coding Tool / Agent Workflow
```

Early versions included:

```text
Keyboard device
→ BLE / HID
→ Computer
→ BLE bridge / TCP interface
→ Host software / config tool
→ Claude hook / agent status reporter
```

Notes:

- This repository mainly contains device-side firmware and hardware-related materials
- Desktop clients, config tools, hooks, and workflows will be gradually moved to public or separate repositories
- For public protocol and third-party client development, please start with `AhakeyAI/protocol`

---

## Build environment

Early firmware projects use:

- IDE: `MounRiver Studio`
- Flash tool: `WCHISP Studio`
- Chip / SDK: WCH CH58x series SDK

Reference SDK:

```text
https://www.wch.cn/downloads/CH583EVT_ZIP.html
```

---

## How to build

Reference workflow:

```text
1. Download the official WCH SDK
2. Place the project code into the SDK example directory, such as EXAM/BLE
3. Open HID_Keyboard_582m_vibe_coding.wvproj
4. Build with MounRiver Studio
5. The output is usually generated under obj/
```

Example output file:

```text
obj/HID_Keyboard_582m_vibe_coding.hex
```

SDK versions, project paths, and chip models may differ. Please follow the actual project files in this repository.

---

## How to flash

Reference workflow:

```text
1. Install WCHISP Studio
2. Put the chip into boot mode
3. Flash the firmware via USB
4. Test buttons, BLE, OLED, RGB, toggle switch, and related functions
```

For more detailed download, flashing, and visual instructions, see:

[Release v1.0 download and flashing guide](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/releases/tag/v1.0)

Notes:

- Boot pins and flashing methods may differ across hardware versions
- Flashing custom firmware may cause unexpected device behavior
- Please make sure you understand the risk before testing
- Do not provide unreviewed modified firmware to general users

---

## Feedback and contributions

If you want to submit changes, experiments, or suggestions to AhaKey, please use the contribution repository:

[AhaKey-X1-hardware-contributions](https://github.com/AhakeyAI/AhaKey-X1-hardware-contributions)

Recommended workflow:

```text
Read the official baseline in this repository
→ Clone locally
→ Modify, build, and test locally
→ Identify the type of your change
→ Create a new branch in the contribution repository
→ Submit your proposal / patch / experiment / docs to the new branch
→ Open a Pull Request, or send the branch link to the AhaKey team
→ AhaKey team reviews it
→ Suitable changes may be cleaned up and merged into the official baseline by maintainers
→ Officially tested changes may be included in a future Release
```

**Always create a new branch for your submission. Do not commit directly to the `main` / `master` branch.**

This helps:

- keep the contributor’s GitHub identity and commit history clear
- make review, discussion, and traceability easier
- prevent personal experiments from affecting the official baseline or the contribution repo’s main branch
- make it easier to thank contributors accurately in future Release notes

Recommended branch names:

```text
fix/<github-id>-short-description
docs/<github-id>-short-description
experiment/<github-id>-short-description
proposal/<github-id>-short-description
```

A good contribution note should include:

- what changed
- why it is needed
- whether it changes the default interaction logic
- how it was tested
- affected device or firmware version
- logs, screenshots, serial output, or testing notes if helpful

Not every experimental change will be merged into the official firmware. Some ideas may remain as local experiments, community notes, or candidate features for future versions.

---

## Contact

For questions about this repository, access permission, flashing, debugging, hardware materials, or collaboration, please contact the AhaKey team.

<p align="center">
  <img src="https://github.com/AhakeyAI/.github/blob/main/profile/assets/qr/wecom-support.png?raw=true" width="180" alt="AhaKey WeCom Support QR Code">
</p>

<p align="center">
  WeCom support
</p>

You can also contact us by email:

```text
zhangxinyang@ahakey.cn
```

<p align="right"><a href="#top">↑ Back to top</a></p>
