# Connect and Talk 交接入口

更新：2026-10-22。仓库 `AhakeyAI/desktop`，接续分支 `connect&talk`。旧mac客户端0.2.3的WS1/WS2/CP2已分批开发和验收，不依赖Runtime。当前进度以适配状态表、WBS CSV及完整交接末段为准。

先阅读 [当前适配状态](../ahastudio/ws3-adaptation-status-2026-10-21.md) 和 [完整交接](./CONNECT_AND_TALK_HANDOFF.md) 末段。Consumer Voice已认可，F5备选暂缓。

## 当前接续规则

本轮开发已统一到 `connect&talk`，旧的21个工作分支与1个原型分支已合入或归档后清理。后续直接在统一分支推进，不再按WBS逐项建立远程分支。先读[最新总WBS](../ahastudio/mac-adaptation-master-wbs-2026-10-22.md)及[分支整合与恢复记录](../ahastudio/connect-talk-branch-consolidation-2026-10-22.md)，再读历史材料。

## 文件索引

- [完整交接](./CONNECT_AND_TALK_HANDOFF.md)
- [当前固件优化8项清单](./FIRMWARE_OPTIMIZATION_LIST_2026-10-21.md)（已反馈至[固件Issue #7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7)）
- [历史固件协作提醒](./FIRMWARE_FOLLOW_UP_2026-10-09.md)
- [适配计划](../ahastudio/legacy-macos-ws12-adaptation-plan-2026-10-08.md)
- [WBS](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.md)
- [WBS CSV](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.csv)
- [前置依赖与对方答复](../ahastudio/legacy-macos-firmware-adaptation-prerequisites-2026-10-08.md)
- [历史F5备选草案（暂缓）](../ahastudio/firmware-macos-f5-dictation-request-2026-10-09.md)
- [原始 WS1/WS2 固件交接](./source/WS1_WS2_FIRMWARE_AND_HOST_HANDOFF.md)

## 另一台设备接续

```sh
git clone https://github.com/AhakeyAI/desktop.git
cd desktop
git switch 'connect&talk'
```

将 `docs/handoff/CONNECT_AND_TALK_HANDOFF.md` 交给下一位Agent。分支名称含 `&`，终端命令需加引号。先核对最新分支与固件身份，再按状态表、WBS和交接末段继续开发/回归；保留用户已验证的键位、语音与素材。
