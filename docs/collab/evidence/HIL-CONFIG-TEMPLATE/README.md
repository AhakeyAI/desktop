# HIL-CONFIG 证据索引（空白模板，待 USER-GATE 后启用）

执行前复制本目录为 `HIL-CONFIG-<YYYYMMDD>/` 再填写；本模板目录保持空白。

## 基线信息（执行时填写）
- accepted 基线 commit：`19eb4dc`（WBS-5.6）
- agent 构建时间 / sha256：待填
- 临时 launchd 标签：`lab.jawa.ahakeyconfig.agent.hil`

## 用例记录（每用例一张，模板见 cases/）
| # | 用例 | 结果 | 证据文件 |
|---|------|------|----------|
| C1 | 图片+基础配置成功 | 未执行 | |
| C2 | 容量拒绝零写入 | 未执行 | |
| C3 | 取消 | 未执行 | |
| C4 | 断电恢复 | 未执行 | |
| C5 | 断连恢复 | 未执行 | |
| C6 | partial resume | 未执行 | |

## 回滚确认
- [ ] bootout 完成
- [ ] plist 已删除
- [ ] launchctl print 无残留
- [ ] 正式登记（如有）已恢复原状
