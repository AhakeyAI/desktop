# 任务卡 WBS-1-UNIFIED-FIRMWARE：统一 Standard/Rhino 固件基线

计划/WBS：1.1-1.7  
状态：`active / 1.4`（Cursor ACK；只做事务化 factory assets）
执行 owner：Cursor  
基线：GitHub `dev@3e7f900ae6f5fe71d57a03da973d79356afea1b6`；Rhino 只读来源为 Gitee `rhino@53cd0a97e95e3b8b35cd56ed2284970d5a79d1be` 与本地 `rhino@00eb7efc235770d0a40e23a8c6e7449b2c010765`  
目标：建立单一源码、两份出厂资源 pack 的统一固件，保留 GitHub SDK/自动关机与 Rhino OLED/资源/上传修复。

允许修改：独立工作区 `/Users/heartline/Documents/Codex/AhaKey-X1-unified-firmware/**`、本卡执行记录与 append-only board。新工作区从 GitHub 冻结基线创建本地分支 `cursor/wbs-1-unified-firmware`。  
禁止：不修改 Studio/Runtime；不修改 `/Users/heartline/Documents/Codex/ahakeyconfig-latest-task-gif` 的现有 dirty Rhino 工作树；两种产品不得形成行为 fork；不覆盖或推送原 GitHub/Gitee 分支；不刷机、不连接量产烧录器、不发布固件。  
完成定义：可重复工具链；SDK bridge/自动关机；Rhino 四状态/双任务图；事务化 factory assets；图片恢复/槽位保护；USB/BLE 身份与 VBUS；Standard/Rhino 两资源 pack；两产物除资源外行为一致。  
测试：两变体 clean build、静态尺寸预算、现有功能回归、上传/传输 HIL；`git diff --check`。  
前置：WBS 0 accepted；用户于 2026-08-26 明确解除“客户端测试后再启动固件”暂缓门禁。与客户端 WBS 5.6 并行仅因仓库和路径完全隔离。

首个检查点（Cursor 完成后停手并提审，不直接进入 1.3）：

1. 在冻结路径建立独立 clone/worktree 和本地分支，证明 HEAD 为 GitHub 冻结 SHA；不 push。
2. 固化可重复工具链、构建命令、编译器/SDK 版本和依赖获取方式。
3. 对 GitHub、Gitee Rhino、本地 Rhino 三个冻结点生成 clean build、map/size 或明确的 missing 证据，补齐 WBS 0.2 Flash 矩阵所需数据。
4. 输出 1.2–1.7 的文件级迁移清单、opcode/Flash 冲突表和回滚点；此检查点不做大规模功能移植。
5. 回传 `git status`、提交 SHA、构建日志摘要、产物哈希及未取得的 SDK/HIL 证据。Codex 验收后才授权进入 1.2–1.7 实现。

## 执行记录（append-only）

### 2026-08-26 Codex 调度

- 用户已确认启动固件部分；本卡晋级 `ready`，owner 改为 Cursor。
- 只授权上述首个检查点。Cursor 接单后把状态改为 `active` 并在 board 末尾 ACK。
- Kimi 继续唯一写入客户端 WBS 5.6；Cursor 不得触碰 `ahakeyconfig-mac/**`、客户端 Shared/Agent 或 WBS 5.6 任务卡。
- 实机刷写、远端 push、量产切换仍为 USER-GATE，本次没有授权。

### [2026-08-26 12:28] Cursor ACK

- ACK 12:20。本卡 `ready` → `active`。只写独立固件工作区，不改客户端。首检查点：clone/分支、工具链、三基线构建证据、1.2–1.7 迁移清单。不刷机、不 push。

### [2026-08-26 12:42] Cursor 首检查点提审

- 独立 clone HEAD = `3e7f900ae6f5fe71d57a03da973d79356afea1b6`，分支 `cursor/wbs-1-unified-firmware`，未 push。
- 未切 Cursor agent root 到固件仓（`feat/unified-client` fetch 会失败）；写入用绝对路径。未改 `ahakeyconfig-latest-task-gif` dirty 树。
- 工具链：CLI Makefile 已放入固件仓根；SDK = `ahakeyconfig-main/.toolchain/ch582sdk`；`Link.ld` FLASH 448K / RAM 32K；`EEPROM_BLOCK_SIZE=4096`。本机 `riscv64-elf-gcc` 16.1.0 **无 newlib**，三基线 clean build 均在 `stdint.h` 失败（日志 `.wbs1-baselines/logs/`）。
- HEX：GitHub obj 403.3 KiB 实填；git `obj_final` 在三 SHA 上为同一 430.9 KiB blob，不能当 Rhino 体积；Rhino 工作树 obj / dist v11 占用 215.8 / 215.5 KiB。
- 冲突：GitHub 无 `0x99`；Rhino `0x95`/`0x84` 与 GitHub 语义冲突；factory 节 0x50000 与 GitHub 403KiB 镜像重叠。
- 报告：`/Users/heartline/Documents/Codex/AhaKey-X1-unified-firmware/docs/wbs-1-checkpoint-1.md`
- 停手，不进入 1.2–1.7 实现。不刷机。

### [2026-08-26 14:04] Cursor 1.1R 提审

- ACK 12:52。xpack 13.2.0 newlib（SHA `a16426a4…fb63dac`）+ **ch583sdk**。未 sudo、未改 dirty Rhino 树。
- 三基线均已 link 出 ELF/map/hex。Rhino 两冻结点分区门禁 PASS（app ~0x2F400）。GitHub 门禁 FAIL（`.text` 至 0x6B600），符合「资源须迁出 App」。
- opcode 报告已按 12:52 更正：0x84/85 同义；0x95 非冲突；0x9C–0x9F 给 v4。0x86 自动关机在 GitHub 有、Rhino `command_solve` 本冻结无，保留 GitHub。
- 报告与脚本：`docs/wbs-1-checkpoint-1.md`、`build-mac.sh`、`tools/check-flash-layout.py`。固件仓提交 `b4f9cc4`。不刷机、不 push、不进入 1.2。

### [2026-08-26 14:50] Cursor 1.1R2 提审

- ACK 14:16。Harness fail-closed: GitHub 必须 link OK 且 `--mode app` 退出 1；Rhino 必须 `.frozen-sha` 匹配且 factory gate 退出 0。空 objdump 退出 2。负向测试在 `tools/test-check-flash-layout.sh`。
- xPack 官方 darwin-arm64 archive SHA `dfe3123e…c45e848fd8a7`；`.toolchain/` 为解压目录非 symlink。SDK manifest `docs/pins/ch583sdk-EVT-EXAM.sha256`。
- GitHub `app_end=0x6C280`。Rhino maps 为 GNU ld `-Map`。`FLASH_GATE=off` + deps stamp 防 stale ELF。
- 报告：`docs/wbs-1-checkpoint-1.md`。固件仓提交 `db2cadc`。不刷机、不 push、不进入 1.2。

### [2026-08-26 12:52] Codex 首检查点复验：证据框架通过，继续 1.1R

- 通过项：独立路径/冻结 SHA/只读 Rhino 提取成立；未修改客户端和 dirty Rhino；三份构建日志真实复现为缺 newlib 的 `stdint.h` 失败；Link.ld、EEPROM、既有 HEX 哈希与 Flash 重叠证据可追溯。无需切换 Cursor agent root，继续使用绝对路径。
- 检查点尚未最终 accepted：固件仓仍只有基线 HEAD，`.gitignore`、`Makefile`、报告尚未提交；clean build/map 仍缺；报告的 opcode“冲突”判断有两处错误。
- 协议裁决：
  1. `0x84` 在 GitHub/Rhino 都是 AI 状态灯效映射；`0x85` 是亮度、`0x86` 是自动关机，保留原号原语义。
  2. `0x95` 在 GitHub 固件中缺失，不构成同号冲突；Rhino `0x95` payload 与当前客户端冻结的 `bindTaskPicture(mode,set,state,start,count,interval)` 相同，直接作为统一语义；`0x96-0x99` 依次保留 query/active-set/finish/capabilities。
  3. 当前客户端已冻结 `0x9A=session abort`、`0x9B=session prepare`；总计划原先把 0x9A/0x9B 分配给平台/动作是过时冲突，统一 v4 新命令顺延为 `0x9C-0x9F`。
- Flash 裁决：固定分区暂定 App `[0x00000,0x50000)`（320 KiB）、trigger `[0x50000,0x51000)`（4 KiB）、单个构建变体的 factory pack `[0x51000,0x70000)`（124 KiB）。Standard/Rhino 分别生成 pack，不在同一镜像内同时放两份。GitHub 403 KiB 旧镜像不能直接作为 App 段；应把产品资源从低位代码/rodata 迁入 pack，使非 pack 链接终点 `<0x50000`，并用 linker ASSERT/size gate 固化。clean map 出来前该布局为候选冻结，不进入功能移植。
- 只授权下一检查点 `1.1R`：修正报告；在固件目录内固定 repo-local、带 newlib 的兼容工具链并记录来源/hash（禁止 sudo 和系统全局修改）；三冻结点 clean build并产出 ELF/map/hex/hash/分段尺寸；验证分区并增加 ASSERT/size gate；提交 Makefile、`.gitignore`、报告与可重复构建脚本/清单。大型工具链和产物保持 gitignored。
- 未授权 1.2–1.7 功能移植、刷机、push 或发布。1.1R 提审通过后再开 1.2。

### [2026-08-26 14:16] Codex 复验 `b4f9cc4`：继续 1.1R2，未开 1.2

- 验收范围 `3e7f900...b4f9cc4`。已独立确认：固件仓 HEAD/分支正确且 clean；三套 ELF/HEX 存在，报告中的 artifact SHA-256 与文件一致；真实 gate 输出为 GitHub `app_end=0x6C280` FAIL、Gitee `0x2F378` PASS、本地 `0x2F400` PASS；opcode 更正正确；无刷机、push 或 1.2 实现。
- 仍不能验收 1.1R，构建/门禁基础设施有以下阻塞：
  1. `tools/build-three-baselines.sh` 对 `make`/gate 使用 `set +e` 后只打印退出码，不断言预期结果；编译、链接或 Rhino gate 失败仍可能让总脚本退出 0。GitHub 也未区分“成功 link 后预期 layout fail”和普通编译失败。
  2. 脚本仅信任目录名，不验证 GitHub/Gitee/本地提取树确实对应三个冻结 SHA；gitignored baseline 目录缺少可重建的 archive/manifest 流程。
  3. Rhino 构建后把真正 linker `.map` 覆盖成 `objdump -h -t` 文本；当前两份 Rhino map hash 不是 linker map。
  4. `build-mac.sh` 默认不 clean，Makefile 的 ELF 未依赖 Makefile、Link.ld、SDK 静态库、工具链/flags stamp，可能对变更后的依赖复用旧产物并错误通过。
  5. Flash checker 在解析不到任何 section 时返回 0（已用 `/bin/echo` 作为 objdump 复现）；也不强制 factory build 必须存在精确 4 KiB `.factory_trigger` 和 `.factory_assets`，属于 fail-open。
  6. 工具链所谓 repo-local 实际是指向 dirty Rhino 仓的绝对 symlink；只校验单个 gcc binary，没有官方 archive URL/SHA、完整工具链校验，也没有 ch583sdk 版本/manifest/hash。clean clone 无法复现。
  7. 报告 GitHub 行只写 `.text` end `0x6B600`，真实 App load end 含 `.data` 为 `0x6C280`；`git diff --check 3e7f900...b4f9cc4` 还有 Markdown trailing whitespace。
- 只授权 `1.1R2`：门禁全路径 fail-closed；三基线身份可验证/可重新提取；保留真实 linker map；clean 或 dependency stamp 防旧产物；Flash parser 空结果失败并按模式要求 factory sections；提交可从 clean clone 获取并校验的工具链/SDK pin（下载来源、archive SHA、SDK manifest/hash，禁止依赖另一 dirty repo绝对路径）；修正 app_end 与 diff check。补负向测试证明每个失败条件返回非零。
- 仍禁止 1.2–1.7、刷机、push、发布。新提交后停手提审。

### [2026-08-26 15:12] Codex 复验 `db2cadc`：继续 1.1R3，未开 1.2

- 验收范围 `b4f9cc4...db2cadc`。独立复跑确认：脚本语法、Flash 负向测试、SDK 当前清单校验、三基线 clean harness 与 `git diff --check` 均通过；GitHub link 成功后 gate 精确退出 1，两份 Rhino gate 退出 0，三份产物保留 GNU ld map；没有进入 1.2、刷机或 push。
- 1.1R2 仍不能 accepted，原因不是“构建跑不通”，而是冻结输入和证据链仍可 fail-open：
  1. GitHub 身份检查只对 tracked `APP/Profile` 做 `git diff --quiet`，未跟踪/ignored `.c` 不会被发现，却会被 Makefile wildcard 编译。必须改为从冻结 SHA 的 `git archive` 构建并只叠加受版本控制的 harness，或用闭集清单拒绝所有未声明的构建输入。
  2. SDK manifest 只校验列出的文件，不拒绝 wildcard 路径下的额外 `.c`；工具链已存在时 arm64 只校验 gcc、x86_64 不校验任何已安装文件。必须对 Makefile 实际消费的 SDK 文件做集合相等校验，并对两种架构的完整构建工具/库做可重复的 archive/安装清单校验；不得以“gcc 可执行”代替完整工具链完整性。
  3. 冻结源码含 `__TIME__`。并行 clean build 会因两个时间字符串是否合并而令 GitHub `app_end` 在 `0x6C280/0x6C28C` 间变化；连续复跑的 ELF/HEX/map 哈希与报告均不一致，Gitee 实测 `0x2F378` 而报告写 `0x2F384`。必须从冻结 commit 固定 `SOURCE_DATE_EPOCH`（或等价去时钟输入），在两个全新输出目录连续构建并证明 ELF/HEX 与尺寸一致；map 若含绝对路径须归一化后比较。报告必须由最终一次封闭运行自动生成，禁止手抄陈旧哈希。
  4. `.deps-stamp` 只记录变量、变量变化却不会使 stamp 失效；`KEEP_OBJ=1`/直接 make 可复用不兼容对象。改为内容寻址依赖键/主动比较并 clean，或删除 `KEEP_OBJ` 并禁止非 clean 入口。
  5. 负向测试不能只覆盖 Flash parser。必须覆盖：GitHub 未跟踪/额外构建输入、错误 frozen SHA、Rhino `.frozen-sha`/commit 缺失、make/link 失败、伪/缺 linker map、损坏工具链/SDK、变量变化后的 stale object；每条断言总 harness 非 0。Flash 侧另补错误 trigger size/address、missing/out-of-window pack。
- 只授权 `1.1R3` 完成上述闭集输入、确定性构建、完整依赖校验、真实负向 harness 与自动证据报告。完成后新 commit 停手提审。状态继续 `active`；仍禁止 1.2–1.7、刷机、push、发布。

### [2026-08-26 15:50] Cursor 1.1R3 完成并停手

- 固件仓 `cursor/wbs-1-unified-firmware` HEAD `04b02715076c35bdbf96c728b865442b7113cc74`（范围 `db2cadc...04b0271`）。未 push、未刷机、未开 1.2。
- GitHub 从 `3e7f900` `git archive` 构建并只叠加受版本控制 harness；`APP`/`Profile` 闭集清单拒绝额外源码。Rhino 提取同样闭集 + `.frozen-sha`。
- SDK 对 Makefile 消费集合做相等校验并哈希；xpack 校验 host 安装文件，并另验 darwin-x64 archive+安装 pin。
- `SOURCE_DATE_EPOCH=0` 与冻结 `__DATE__`/`__TIME__`；两个全新 `OUT_DIR` ELF/HEX 一致，map 归一化后一致。删除 `KEEP_OBJ`；deps key 变化会 clean。
- 负向：额外 APP 源、错误/缺失 frozen SHA、缺失 Rhino commit、伪/缺 map、make 失败、SDK extra `.c`、损坏工具链、CFLAGS 变化后 stale object；Flash 补 trigger size/address、missing/out-of-window pack。
- 最终报告由 harness 写入 `docs/wbs-1-checkpoint-1.md`：GitHub gate=1 `app_end=0x6C280`；Gitee gate=0 `0x2F378`；Local gate=0 `0x2F400`。

### [2026-08-26 17:24] Codex 复验 `04b0271`：主体通过，继续最小 1.1R4

- `lastReviewedCommit: 04b02715076c35bdbf96c728b865442b7113cc74`。验收范围 `db2cadc...04b0271`。已独立确认：shell/Python 语法、Flash 全组负向、闭集 APP 负向、SDK consumed-set + hash、依赖键重建、当前 arm64 install pin 均通过；GitHub archive/确定性时钟/双 OUT_DIR 比较、SDK 闭集和自动报告均为真实实现；未进入 1.2、刷机或 push。
- 1.1R3 暂不 accepted，剩余问题收敛为证据闭合，不再推翻 harness：
  1. 工具链 install pin 仍只列 10 项。GCC 实际调用但未 pin 的包括 `libexec/.../cc1`、`collect2`、`riscv-none-elf/bin/as` 与内部 `riscv-none-elf/bin/ld`；当前 pin 的 `bin/riscv-none-elf-ld` 甚至不是本次 GCC 解析出的 ld。缓存安装中这些文件漂移仍会改变 ELF/HEX而通过校验。按 `gcc -print-prog-name` / `-print-file-name` 与实际 link closure 补齐 arm64/x64 pin，或校验完整解压树。
  2. 双 clean 一致性只对 GitHub 执行；Gitee/Local Rhino 各只 build 一次。三冻结点都必须在两个独立 extract/output root 中比较 ELF、HEX、size 与 normalized map。
  3. wrong/missing `.frozen-sha` 负向测试只在脚本里手工比较/判断文件，未调用生产 `rhino_build` guard；make/link failure 也只跑 toy Makefile。抽出生产共用 validator/runner，让负向用同一入口，并断言总 baseline harness/该生产入口非零；删除自证式测试。
  4. GitHub overlay 从当前可变 working tree `cp` Makefile/tools/pins。必须从明确的 committed harness tree/archive 叠加，或在入口拒绝 tracked/untracked overlay 漂移；不能让未提交 harness 改动影响“冻结运行”。
  5. 报告记录 `HEAD=db2cadc`，提交却是 `04b0271`，且 size blob 带本机绝对路径。采用两提交证据流程：先提交并保持 clean 的 harness commit `H`，从 `H` 运行门禁并生成只记录 `harnessCommit=H`、相对/归一化路径的报告，再以仅含报告的 evidence commit `E` 提审；不要做自引用 HEAD。报告生成后必须用重跑/compare 证明无陈旧数据。
  6. `tools/testdata/stamp-probe/hello.c` 多一行空白，`git diff --check db2cadc...04b0271` 实际告警；修正并把 diff check 作为真实门禁。
- 只授权最小 `1.1R4` 关闭以上六项。完成后以 `H + E` 两个 commit 停手提审；通过即 accepted 首检查点并开放 1.2。仍禁止 1.2–1.7、刷机、push、发布。

### [2026-08-26 17:33] Cursor 1.1R4 完成并停手

- 固件仓 `cursor/wbs-1-unified-firmware`。Harness `H=544c1fcaf927f0d4a6db655314213c53652a635d`（含前置 `022b6ae` 编译链 pin/overlay，以及 `H` 上保留调用方 `SOURCE_DATE_EPOCH` 的生产 make runner）。Evidence `E=cec02f80a907ebfc6f89d1db580af434b2870efa` 仅含生成报告。验收范围建议 `04b0271...cec02f8`。未 push、未刷机、未开 1.2。
- 工具链 pin 补齐 `cc1`/`collect2`/`riscv-none-elf/bin/as`/`riscv-none-elf/bin/ld`；host `gcc -print-prog-name` 对相对路径断言；x64 仍只验 archive+install pin。
- GitHub/Gitee/Local 均双独立 extract+build；ELF/HEX/size/normalized map 一致。Overlay 来自 `git archive HEAD`；入口拒绝 dirty/untracked Makefile/tools/pins。
- 负向复用 `verify-rhino-identity.sh`、`run-firmware-make.sh`、`extract-rhino-baselines.sh`、生产 Makefile `prepare-out`、`verify-toolchain-install.sh`/`verify-sdk.py`。`git diff --check freeze...HEAD` 为门禁；`hello.c` 空行已删。
- 在 clean `H` 上跑门禁后写入报告：`harnessCommit=544c1fc`（不是 `E`）；size 仅相对文件名。GitHub gate=1 `app_end=0x6C280` ELF `cc4b9048…`；Gitee gate=0 `0x2F378` ELF `9719ace8…`；Local gate=0 `0x2F400` ELF `03edf91b…`。

### [2026-08-26 17:43] Codex：1.1R4 accepted，只开放 1.2

- `lastReviewedCommit: cec02f80a907ebfc6f89d1db580af434b2870efa`；验收范围 `04b0271...cec02f8`。Harness `H=544c1fc` 与仅报告 Evidence `E=cec02f8` 的两提交证据链成立。
- Codex 独立复验：生产负向 suite、arm64 安装闭包、x64 完整归档 SHA+临时解包闭包、SDK 24 文件 consumed-set，三基线 ELF/HEX/size/normalized map 双构建一致均通过；报告哈希与留存产物一致。
- 独立 Flash gate：GitHub `exit 1 / app_end=0x6C280`；Gitee `exit 0 / 0x2F378`；Local `exit 0 / 0x2F400`。`git diff --check` 干净；无 1.2 实现、刷机或 push 越界。
- x64 疑问不阻断：其每次从已验证完整 archive SHA 的官方包解压到临时目录，不依赖可漂移的持久安装；实际闭包 13 文件亦复验通过。若日后支持 Intel Mac CI，再在该 host 上补 GCC 路径解析运行证据。
- 非阻塞 P3：`build-three-baselines.sh` 与 `compare-repro-artifacts.py` 各自解析 `size` 输出；后续可归并为单一结果采集器，不阻断 1.2。
- **开放 1.2，仅限“保留 GitHub SDK bridge / 自动关机基线能力”**：
  1. 冻结并测试 SDK bridge 的 default-off 产品语义，以及 enable 时 init/loop/key/lever/AI/custom-command 路由；不得默认开启 SDK。
  2. 冻结 `0x86` 自动关机的原 opcode、payload 校验、持久化与定时生效语义，不重编号、不改 Studio/Runtime。
  3. 默认产品构建与 SDK-enabled 构建均须 clean link；持续通过 Flash gate 和现有 harness，记录体积增量。
  4. 仅改固件独立仓与本卡/看板；不移植 Rhino OLED/factory assets/上传恢复（分别属 1.3–1.5），不做 1.6/1.7。
  5. 新 commit 后停手提审；仍禁止刷机、push、量产切换。

### [2026-08-26 17:56] Cursor ACK 1.2

- ACK 17:43。基线 `cec02f8`。施工范围仅 1.2：SDK default-off + enable 路由证据、`0x86` 语义冻结、双构建体积。不进 OLED/factory/上传/1.6/1.7。

### [2026-08-26 17:59] Cursor 1.2 完成并停手

- 固件仓 `H=d6b26022519355c6ada2a731ea92c7af96ea419e`（含 `ed227ef` Makefile 显式 `AHAKEY_SDK_ENABLE=1` 变体、host 0x86 模型与源码契约）。Evidence `E=6996fc21e9509cf2c519d321e384c8006e644092` 仅 `docs/wbs-1.2-sdk-bridge.md`。验收范围建议 `cec02f8...6996fc2`。未 push、未刷机、未进 1.3–1.7。
- 产品默认仍为 header `AHAKEY_SDK_ENABLE 0`；默认 GitHub ELF SHA 与 1.1R4 相同 `cc4b9048…`，gate=1 `app_end=0x6C280`。`make AHAKEY_SDK_ENABLE=1` 链接 in-tree bridge（不含缺头文件的 `public_api.c`），ELF `3d156978…`，gate=1 `app_end=0x6C270`，`dec` +304。
- 源码契约：init/loop/key/lever/AI/`0xA0–0xEF` 均在 `AHAKEY_SDK_ENABLE` 后。`0x86` 仍为 query(len=1)/set(len=3 LE uint16，0 关闭，>1440 拒绝)、`have_update_custom_data` 持久化、`minutes*60` 1Hz 定时。

### [2026-08-26 18:15] Codex：1.2 主体通过，最小 1.2R1 证据返工

- `lastReviewedCommit: 6996fc21e9509cf2c519d321e384c8006e644092`；验收范围 `cec02f8...6996fc2`。未开放 1.3。
- 已独立复验：默认 ELF `cc4b9048…` 与 1.1 一致；SDK-on ELF `3d156978…`；`dec +304`；六个 bridge 符号进入 SDK-on ELF；默认无 SDK 符号；两构建 gate 均按预期退出 1；H/E 报告链、diff check 和范围约束成立。
- Standards：无 P1/P2；非阻塞 P3 为第三份 artifact/`size` 解析实现，后续应与现有 collector 合并。
- 状态保持 `active`，原因是测试真实性，不是已发现产品行为回退：
  1. **P1：`0x86` 可执行测试运行的是 `tools/wbs12/auto_power_off_model.c` 复制模型，不是生产 `command_solve.c` / `main.c` / `fram_RC16.c` 使用的逻辑。** 复制模型可与生产代码分叉但仍全绿；Python 字符串存在性检查不能证明返回码、持久化或倒计时无 off-by-one。
  2. **P2：SDK gate 仅检查定义符号+源码文本。** 当前 ELF 反汇编可见六个生产调用引用，但 harness 未把 caller→callee 关系写成回归门禁。
- 只授权最小 1.2R1，不扩架构：
  1. 删除独立复制的 auto-power-off model。把 query/set/sanitize/timeout/tick 决策收敛为生产固件和 host test **共用的单一 policy 模块**，或以 HAL/transport mock 直接编译执行生产路径。生产 `command_solve`/1Hz event/持久化薄接线必须调用该单一决策源，host test 必须链接同一份实现。
  2. SDK-on ELF 门禁增加六个核心路由的 caller→callee 引用断言（反汇编/relocation 或等价 strong-callback 集成测试），不仅是“目标符号存在”。
  3. 报告明确称为 **internal bridge-enabled variant**；`public_api.c` 因缺外部 `ahakey-firmware-sdk` 未链入，不得宣称完整公共 SDK 已恢复。完整 SDK 发布链另立后续任务，本轮不引入外部仓。
  4. 重跑默认/bridge-enabled clean link、Flash gate、产物哈希/体积、生产 policy test；新 H+E 后停手提审。仍不刷机、不 push、不进 1.3–1.7。

### [2026-08-26 20:14] Cursor ACK 1.2R1

- ACK 18:15。最小返工：共用 auto-power-off policy、六路 ELF 调用链、internal bridge 措辞。不开 1.3。

### [2026-08-26 20:16] Cursor 1.2R1 完成并停手

- Harness `H=840778c5dba05979c6d26ea700d2568a61e2a3db`。Evidence `E` 仅 `docs/wbs-1.2-sdk-bridge.md`。验收范围建议 `6996fc2...` 新 E。未 push、未刷机、未开 1.3。
- 删除复制模型。`APP/sub_main/auto_power_off.c` 为生产+host 同一 policy；`command_solve` 经 `apo_apply_command` 薄接线 persist/refresh；1Hz 经 `apo_tick`。GitHub overlay 绑定这些生产文件。
- Internal bridge ELF 六路 caller→callee objdump 门禁通过；默认 ELF 六路 absent。`public_api.c` 未链入，报告写明非公共 SDK。
- 默认 gate=1 `app_end=0x6C338` ELF `c8c42ffb…`；internal-bridge gate=1 `0x6C328` ELF `e4cbeac2…`；`dec` +304。

- 更正：Evidence `E=105250c2ee5248e4f4f916d7e88e2221163417d9`。验收范围 `6996fc2...105250c`。

### [2026-08-26 22:11] Codex：1.2R1 accepted，只开放 1.3

- `lastReviewedCommit: 105250c2ee5248e4f4f916d7e88e2221163417d9`；验收范围 `6996fc2...105250c`。Harness `H=840778c` 与仅报告 Evidence `E=105250c` 的两提交证据链成立，固件工作树 clean，`git diff --check` 通过。
- Standards：无 P1/P2。生产与 host test 共用 `APP/sub_main/auto_power_off.c`；原复制模型已删除。非阻塞 P3 仍是构建脚本存在多处 artifact/size 解析，后续可归并，不阻断 1.3。双代理复核因当轮用量限制未返回结果；Codex 已独立完成同等的源码、差异和可执行门禁复核。
- Spec：`0x86` query/set/sanitize/persist/refresh/1Hz tick 均经同一 policy；默认构建六条 SDK 调用链均 absent，internal bridge 构建六条 caller→callee 均 present。报告正确限定为 internal bridge，未将未链接的 `public_api.c` 宣称为公共 SDK。
- 独立门禁：生产 policy test 通过；默认 ELF `c8c42ffb…`、gate=1、`app_end=0x6C338`；internal bridge ELF `e4cbeac2…`、gate=1、`app_end=0x6C328`；体积差 `dec +304`。未刷机、未 push、未进入 1.3 越界。
- **开放 1.3，仅限“Rhino 四状态与双套任务图移植”**：
  1. 继续以 GitHub `master/dev` 同树为产品源，在当前 `105250c` 基线上移植 Rhino 的四状态 OLED 状态机和两套任务图 binding/切换；不得切换到或 cherry-pick `eternal-dev` 的 protocol 3。
  2. 命令空间冻结为：`0x95 TASK_PICTURE_BIND(mode/set/state/start/count/interval)`、`0x96 TASK_PICTURE_QUERY`、`0x97 ACTIVE_PICTURE_SET`、`0x98 PICTURE_WRITE_END`、`0x99 CAPABILITIES`。保留既有 `0x93/0x94` 兼容行为、`0x86` 与 SDK bridge，不得重编号。
  3. 先把 Rhino 源码的状态、套图、slot/帧范围和 EEPROM binding 布局整理成文件级迁移清单；对旧 `key_bund`/任务图数据给出 fail-closed 的兼容或迁移策略，禁止未经门禁直接解释旧持久数据。
  4. 测试必须覆盖四状态转换、两套图独立绑定与激活、非法 mode/set/state/range/count/interval 拒绝、查询往返、完成命令、重启后绑定恢复、旧数据兼容，以及默认/internal-bridge 两变体 clean build、Flash gate 和既有 `0x86`/SDK 回归。
  5. 本切片不迁移 factory assets（1.4）、上传恢复/槽位保护（1.5）、USB/VBUS（1.6）或资源 pack（1.7）。若 1.3 依赖这些能力，只定义 seam 并上报，不得顺手实现。
  6. 新 `H + E` 提交后停手提审；仍禁止刷机、push、发布和量产切换。

### [2026-08-26 22:20] Cursor ACK 1.3

- ACK 22:11。基线 `105250c`。只做 1.3：四状态 + `0x95–0x99` 双套任务图；保留 `0x93/0x94` idle 拒绝、`0x86`、SDK bridge。不进 1.4–1.7，不刷机、不 push。

### [2026-08-26 22:42] Cursor ACK 1.3R1

- ACK 22:38。最小返工：0x95 interval、EEPROM round-trip、active set 归零、CL `_Static_assert`、迁移表、caps14 fixture。不改客户端。

### [2026-08-26 22:28] Cursor 1.3 完成并停手

- Harness `H=876bbe55329ce582d4146570ab2a7204d40ca0bc`。Evidence `E=9f29e47e6157ead3a52f2df71a3b7fef3f778219` 仅 `docs/wbs-1.3-task-pictures.md`。验收范围建议 `105250c...9f29e47`。未 push、未刷机、未开 1.4–1.7。
- 生产+host 共用 `task_picture.c`。默认 gate=1 `app_end=0x6CAE8` ELF `c1affe9d…`；internal-bridge gate=1 `0x6CAD0` ELF `27ae7d0e…`；`dec` +296。0x86/SDK 回归通过。

### [2026-08-26 22:38] Codex 复验：1.3 暂不 accepted，最小 1.3R1

- `lastReviewedCommit: 9f29e47e6157ead3a52f2df71a3b7fef3f778219`；验收范围 `105250c...9f29e47`。H/E 两提交成立，固件工作树 clean，`git diff --check`、生产 `task_picture.c` host test、1.2R1 回归、ELF 哈希/size 和两变体 Flash gate 均与报告一致。未越界进入 1.4–1.7、刷机或 push。
- Standards：无仓库硬规则违反。P2 为 `tp_map_claude_to_oled` 依赖 `CL_*` 的裸整数序号，枚举重排会静默错映射；P3 为 WBS 构建/证据脚本重复、图片 binding 继续用裸 `uint16_t[3]`、显示路径丢弃 const。P3 不阻断本轮。
- Spec 阻塞：
  1. **P1：14 字节 `0x99` 与当前客户端的槽位基址语义不兼容。** 固件关闭 factory 位并返回 `userSlotLimit=N`，但客户端 14-byte fallback 将 `factorySlotBase=N`；planner 会从容量末端 N 开始分配，固件随后以 `start+count>N` 拒绝全部 `0x95`。这是跨仓真实链路阻塞，固件单测当前未覆盖。
  2. **P1：`0x95` 未拒绝非法 interval。** 当前只校验 mode/set/state/start/count，`count>1 && interval=0` 仍会持久化，显示循环不会调度下一帧。任务卡要求的非法 interval 门禁缺失。
  3. **P2：重启恢复测试是同一内存数组再次 sanitize，不是持久化往返。** 未证明 `persist → save_key_bound_data → EEPROM_READ → sanitize` 后 binding 和 active set 恢复；也未证明旧短布局读入新尾部时的完整迁移结果。
  4. **P2：缺少先决的文件级迁移清单。** 报告没有列 Rhino source→统一树 destination、移植/舍弃符号、slot/帧边界和 EEPROM 字段/偏移变化。
  5. **P2：合法 magic 下损坏的 `active_set` 用 `%2` 转成有效 set。** 为保持 fail-closed，越界值应回到 set 0，而不是把 `0xFF` 解释成 set 1；query/display 也不得各自重复 modulo 掩盖损坏。
- 只授权最小 `1.3R1`，不开放 1.4：
  1. 对新 `0x95` 冻结 interval：解绑 `count=0` 可忽略/归一化 interval；单帧可不依赖 interval；多帧必须在客户端可产生的安全范围内（当前 1–30 FPS 对应 `33...1000 ms`），否则拒绝且不写 binding。`0x93` 保持既有兼容语义。补边界和无副作用测试。
  2. 增加持久化 round-trip harness：用生产 `key_bund_s` 布局覆盖旧短 EEPROM image→迁移→保存 bytes→新实例 reload/sanitize，断言 set0 迁移、set1 空、active set、binding/interval 均稳定；源码门禁证明 `r.persist` 确实接到 `have_update_custom_data`/保存入口。
  3. `active_set>=TP_SET_COUNT` 一律归零并持久化/在下次保存落盘；display/query 共用已校验值。为 `CL_*` 数值耦合增加生产 `_Static_assert`，或把 named-enum adapter 留在 `main.c`，禁止无门禁裸序号。
  4. 报告补文件级迁移表、EEPROM old/new offset+size、slot/frame 公式、明确延后到 1.4/1.5 的 seam。
  5. 生成与 `tp_write_caps14` 完全相同的 capability fixture/断言；客户端侧解析修复由 Kimi 的 WBS-5.7-R1 独立完成，Cursor 不改客户端。两仓交叉测试必须证明 factory 位关闭的 14-byte frame 得到 `factorySlotBase=0`、`userSlotLimit=N`，首个/末个合法 `0x95` 均可通过，越界拒绝。
  6. 重跑 host/协议交叉 fixture、默认/internal-bridge clean build、Flash gate、`0x86`/SDK 回归和 diff check；新 H+E 后停手提审。仍不刷机、不 push、不进入 1.4–1.7。

### [2026-08-26 22:51] Cursor 1.3R1 完成并停手

- Harness `H=a6d86ea6316078065f8b3a9f9b376fe5ac231f75`。Evidence `E=9135183867a693dbab81aac3b9d4a1b172c34860` 仅 `docs/wbs-1.3-task-pictures.md`。验收范围建议 `9f29e47...9135183`。未 push、未刷机、未开 1.4–1.7，未改客户端。
- `0x95` 多帧 interval `33...1000`，非法拒绝且不写；`0x93` 区间语义不变。`active_set>=2` 归零；`CL_*` `_Static_assert`。旧 2080 字节 EEPROM→迁移→保存 bytes→reload。caps14 `03 04 02 04 33 00 c8 00 20 01 00 00 00 00`，intended `factorySlotBase=0` / `userSlotLimit=288`。
- 默认 gate=1 `app_end=0x6CB1C` ELF `afb50532…`；internal-bridge gate=1 `0x6CB04` ELF `1f1889ce…`；`dec` +296。0x86/SDK 回归通过。

### [2026-08-26 23:18] Codex：1.3R1 固件侧 accepted，联合门禁等待客户端

- `lastReviewedCommit: 9135183867a693dbab81aac3b9d4a1b172c34860`；范围 `9f29e47...9135183`。Harness `H=a6d86ea` 与仅报告 Evidence `E=9135183` 成立，固件工作树 clean，`git diff --check` 干净。
- 独立复验通过：生产 `task_picture.c` host test、1.2 source regression、interval `33...1000`/非法无写、解绑归一化、旧 2080B EEPROM bytes round-trip、损坏 active set 归零、`CL_*` static asserts、精确 caps14 fixture。留存默认/internal-bridge ELF SHA 与报告一致（`afb50532…` / `1f1889ce…`），体积差 `+296`。
- 固件侧 1.3R1 accepted；Cursor 停手，不进入 1.4。整项 1.3 的跨仓状态仍为 active，仅等待 Kimi 在 WBS-5.7-R2 完成 caps14 客户端解析与 planner 交叉测试。该门禁通过后 Codex 再联合关闭 1.3，并决定是否开放 1.4。

### [2026-08-27 01:00] Codex：caps14 交叉门禁通过，WBS-1.3 accepted

- 客户端 `4171111` 已用固件精确 14-byte fixture 完成 factory-off `base=0`、factory-on 短帧 fail-closed、首/末槽与 288 容量越界测试；Codex 独立复跑 5/5 通过。固件 `9135183` 与客户端交叉契约闭合。
- WBS-1.3 现正式 accepted。Cursor 继续停手；本轮暂不开放 1.4，待客户端 WBS-5.7-R3 执行协调器验收通过后再发下一张固件切片，避免同时扩大两个高风险执行面。

### [2026-08-26 23:21] Cursor 确认停手

- ACK 23:18。固件侧 `1.3R1 @ 9135183` 已验收，无新提交、不重复提审。P3 延期。不进入 1.4–1.7，不刷机、不 push、不改客户端。等待 Kimi `5.7-R2` caps14 交叉门禁后由 Codex 联合关闭 1.3。

### [2026-08-27 20:03] Codex：解除暂停，只开放 WBS-1.4 factory assets

- 前置已满足：客户端 WBS-5.7 accepted @ `488097d`；独立固件仓只读复核为 clean，分支 `cursor/wbs-1-unified-firmware`，HEAD `9135183867a693dbab81aac3b9d4a1b172c34860`。Cursor ACK 后翻 active。
- 本切片只移植 Rhino `factory_assets.c/.h` 的事务化出厂资源模块、trigger/manifest/journal 与对应构建/host 门禁；统一产品源码只能有一份，Standard/Rhino 的差异只允许资源 manifest、资源字节、manifest CRC 与只读 variant ID。
- 先形成 Rhino source→统一树 destination 的文件/符号迁移表，冻结 factory Flash 窗口、4 KiB trigger、manifest 版本/CRC、journal 状态机及掉电恢复不变量；不得复用 `0x95–0x99`，不得占用 current `0x9A SESSION_ABORT` / `0x9B SESSION_PREPARE`。
- 必须 fail-closed：trigger/manifest/version/CRC/范围任一非法时不得把 factory 数据解释为用户资源；安装/激活过程需证明 COMMIT 前旧资源仍有效、COMMIT 后新 manifest 与资源一致，掉电窗口可恢复或安全回退。不得在本切片顺手实现 1.5 上传恢复、1.6 USB/VBUS 或 1.7 最终双资源 pack。
- 测试/证据：生产模块与 host test 共用核心状态机；覆盖有效安装、重复幂等、损坏 trigger/manifest/CRC、越界、各事务阶段掉电恢复；默认/internal-bridge 双 clean build、Flash gate、1.2 `0x86`/SDK 与 1.3 `0x95–0x99` 回归；生成新的 Harness H + 仅报告 Evidence E，`git diff --check` 后停手提审。
- 禁止刷机、连接量产烧录器、push、发布或修改客户端仓产品代码。HIL/真机掉电不属于本卡当前授权。

### [2026-08-27 20:12] Cursor ACK WBS-1.4

- ACK 20:03。本卡 `ready` → `active`。只写 `/Users/heartline/Documents/Codex/AhaKey-X1-unified-firmware/**`、本卡与看板。产品源仍为 `9135183` 祖先树，不换 `eternal-dev`。
- 范围：Rhino `factory_assets` 事务化出厂资源模块、trigger/manifest/journal、构建/host 门禁。不进入 1.5–1.7，不占用 `0x9A`/`0x9B`，不复用 `0x95–0x99`。
- 不刷机、不 push、不改客户端产品代码。HIL-CONFIG 真机窗口不由本 ACK 打开。
