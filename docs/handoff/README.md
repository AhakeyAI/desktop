# Connect and Talk 交接入口

日期：2026-10-09。仓库 `AhakeyAI/desktop`，分支 `connect&talk`。此分支基于旧版 main，新增本任务交接文档，未开始新固件适配代码开发。

先阅读 [完整交接](./CONNECT_AND_TALK_HANDOFF.md)，其中记录已确认决策、仍待收口的语音路线，以及下一步开发顺序。

## 文件索引

- [完整交接](./CONNECT_AND_TALK_HANDOFF.md)
- [固件协作提醒清单](./FIRMWARE_FOLLOW_UP_2026-10-09.md)
- [适配计划](../ahastudio/legacy-macos-ws12-adaptation-plan-2026-10-08.md)
- [WBS](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.md)
- [WBS CSV](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.csv)
- [前置依赖与对方答复](../ahastudio/legacy-macos-firmware-adaptation-prerequisites-2026-10-08.md)
- [语音方案比较与固件说明草案](../ahastudio/firmware-macos-f5-dictation-request-2026-10-09.md)
- [原始 WS1/WS2 固件交接](./source/WS1_WS2_FIRMWARE_AND_HOST_HANDOFF.md)

## 另一台设备接续

```sh
git clone https://github.com/AhakeyAI/desktop.git
cd desktop
git switch 'connect&talk'
```

将 `docs/handoff/CONNECT_AND_TALK_HANDOFF.md` 交给下一位 Agent。分支名称含 `&`，终端命令需加引号。继续读取最新固件代码、完成剩余 grill 决策，更新终版计划/WBS，再开始开发。
