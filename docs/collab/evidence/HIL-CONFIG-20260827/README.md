# HIL-CONFIG 2026-08-27 证据索引

执行 owner：Cursor。USB 跳过。C4/C5 前不断电、不断蓝牙。

## 基线信息
- 协作调度 commit：`ca3184b`
- WBS-5.6 accepted：`19eb4dc`；WBS-5.7 accepted：`488097d`
- agent 产物：`/tmp/ahakey-hil-bin/ahakeyconfig-agent`（从 `.build/release` 复制，避免 Documents 路径下 launchd/dyld 挂起）
- sha256：`e7c623f5a82b5dd997f8180c3193898c708d9ceb39a2747d91a83e1e5c3f4191`
- 临时 launchd 标签：`lab.jawa.ahakeyconfig.agent.hil`（**未覆盖**正式 `lab.jawa.ahakeyconfig.agent.plist`）
- 固件仓：`9135183` clean；1.4 暂停

## 用例记录
| # | 用例 | 结果 | 证据文件 |
|---|------|------|----------|
| smoke | XPC 正/负 | 通过 | [00-baseline-and-smoke.md](00-baseline-and-smoke.md) |
| C1 | 图片+基础配置成功 | 未执行 | [cases/C1.md](cases/C1.md) |
| C2 | 容量拒绝零写入 | 未执行 | [cases/C2.md](cases/C2.md) |
| C3 | 取消 | 未执行 | [cases/C3.md](cases/C3.md) |
| C4 | 断电恢复 | 未执行 | [cases/C4.md](cases/C4.md) |
| C5 | 断连恢复 | 未执行 | [cases/C5.md](cases/C5.md) |
| C6 | partial resume | 未执行 | [cases/C6.md](cases/C6.md) |

## 回滚确认
- [ ] bootout 完成
- [ ] HIL plist 已删除
- [ ] launchctl print 无 `agent.hil` 残留
- [ ] 正式 `lab.jawa.ahakeyconfig.agent` 已按备份恢复
